local M = {}

function M.detect()

  local uv = vim.uv or vim.loop
  local sys = uv and uv.os_uname().sysname or ""

  ------------------------------------------------
  -- Windows
  ------------------------------------------------
  if sys == "Windows_NT" or vim.fn.has("win32") == 1 then

    local ffi = require("ffi")

    pcall(ffi.cdef, [[
      typedef unsigned int UINT;
      typedef void* HWND;
      typedef uintptr_t WPARAM;
      typedef intptr_t LPARAM;
      typedef intptr_t LRESULT;

      HWND GetForegroundWindow(void);
      HWND ImmGetDefaultIMEWnd(HWND hWnd);
      LRESULT SendMessageA(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam);
    ]])

    local user32 = ffi.load("user32")
    local imm32 = ffi.load("imm32")

    local WM_IME_CONTROL = 0x0283
    local IMC_GETCONVERSIONMODE = 0x0001
    local IMC_SETCONVERSIONMODE = 0x0002
    local IMC_GETOPENSTATUS = 0x0005
    local IMC_SETOPENSTATUS = 0x0006

    local cached_ime_hwnd = nil

    local function get_ime_hwnd()
      local win = user32.GetForegroundWindow()
      if win ~= nil and win ~= ffi.NULL then
        local ime_win = imm32.ImmGetDefaultIMEWnd(win)
        if ime_win ~= nil and ime_win ~= ffi.NULL then
          cached_ime_hwnd = ime_win
          return ime_win
        end
      end
      return cached_ime_hwnd
    end

    -- Attempt to get IME window handle immediately if Neovim is already foreground
    get_ime_hwnd()

    -- Update IME window handle whenever entering Insert mode
    vim.api.nvim_create_autocmd("InsertEnter", {
      callback = function()
        get_ime_hwnd()
      end,
    })

    return function()
      local ime_hwnd = get_ime_hwnd()
      if ime_hwnd == nil or ime_hwnd == ffi.NULL then
        return
      end

      -- 1. Korean, Japanese, etc. (Close IME / switch to Latin)
      local open_status = user32.SendMessageA(ime_hwnd, WM_IME_CONTROL, IMC_GETOPENSTATUS, 0)
      if open_status ~= 0 then
        user32.SendMessageA(ime_hwnd, WM_IME_CONTROL, IMC_SETOPENSTATUS, 0)
      end

      -- 2. Chinese (Microsoft Pinyin, etc. / switch to Latin conversion mode)
      local conv_mode = user32.SendMessageA(ime_hwnd, WM_IME_CONTROL, IMC_GETCONVERSIONMODE, 0)
      if conv_mode ~= 0 then
        user32.SendMessageA(ime_hwnd, WM_IME_CONTROL, IMC_SETCONVERSIONMODE, 0)
      end
    end
  end

  ------------------------------------------------
  -- WSL (Windows Subsystem for Linux)
  ------------------------------------------------
  local is_wsl = vim.fn.has("wsl") == 1
    or (sys == "Linux" and (vim.env.WSL_DISTRO_NAME ~= nil or vim.env.WSL_INTEROP ~= nil))

  if is_wsl then
    local ps_cmd = nil
    if vim.fn.executable("powershell.exe") == 1 then
      ps_cmd = "powershell.exe"
    elseif vim.fn.executable("/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe") == 1 then
      ps_cmd = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    end

    if ps_cmd then
      local job_id = vim.fn.jobstart({ ps_cmd, "-NoProfile", "-NonInteractive", "-Command", "-" }, {
        pty = false,
        stdin = "pipe",
      })

      if job_id > 0 then
        local init_script = table.concat({
          'Add-Type @"',
          "using System;",
          "using System.Runtime.InteropServices;",
          "public class WinIME {",
          '    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();',
          '    [DllImport("imm32.dll")] public static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hWnd);',
          '    [DllImport("user32.dll")] public static extern IntPtr SendMessageA(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);',
          "    public static void ToLatin() {",
          "        IntPtr fg = GetForegroundWindow();",
          "        if (fg == IntPtr.Zero) return;",
          "        IntPtr ime = ImmGetDefaultIMEWnd(fg);",
          "        if (ime == IntPtr.Zero) return;",
          "        SendMessageA(ime, 0x0283, (IntPtr)0x0006, IntPtr.Zero);",
          "        SendMessageA(ime, 0x0283, (IntPtr)0x0002, IntPtr.Zero);",
          "    }",
          "}",
          '"@',
        }, "\r\n")

        vim.fn.chansend(job_id, init_script .. "\r\n")

        vim.api.nvim_create_autocmd("VimLeavePre", {
          callback = function()
            pcall(vim.fn.chanclose, job_id, "stdin")
          end,
        })

        return function()
          pcall(vim.fn.chansend, job_id, "[WinIME]::ToLatin()\r\n")
        end
      end
    end

    -- Fallback for WSLg (Linux GUI desktop) with fcitx5 / ibus
    if vim.fn.executable("fcitx5-remote") == 1 then
      return function()
        if tonumber(vim.fn.system("fcitx5-remote")) == 2 then
          vim.fn.system("fcitx5-remote -c")
        end
      end
    end

    if vim.fn.executable("ibus") == 1 then
      return function()
        vim.fn.system("ibus engine xkb:us::eng")
      end
    end

    return nil
  end

  ------------------------------------------------
  -- Linux
  ------------------------------------------------
  if sys == "Linux" then

    if vim.fn.executable("fcitx5-remote") == 1 then
      return function()
        if tonumber(vim.fn.system("fcitx5-remote")) == 2 then
          vim.fn.system("fcitx5-remote -c")
        end
      end
    end

    if vim.fn.executable("ibus") == 1 then
      return function()
        vim.fn.system("ibus engine xkb:us::eng")
      end
    end
  end

  ------------------------------------------------
  -- macOS
  ------------------------------------------------
  if sys == "Darwin" then
    if vim.fn.executable("macism") == 1 then
      return function()
        vim.fn.system("macism com.apple.keylayout.ABC")
      end
    end
  end

end

return M