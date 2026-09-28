local M = {}
local wsl_switch

local function linux_switch()
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

function M.detect()
  local uv = vim.uv or vim.loop
  local sys = uv and uv.os_uname().sysname or ""

  ------------------------------------------------
  -- Windows
  ------------------------------------------------
  if sys == "Windows_NT" or vim.fn.has("win32") == 1 then
    local ffi = require("ffi")

    pcall(
      ffi.cdef,
      [[
      typedef unsigned int UINT;
      typedef void* HWND;
      typedef uintptr_t WPARAM;
      typedef intptr_t LPARAM;
      typedef intptr_t LRESULT;

      HWND GetForegroundWindow(void);
      HWND ImmGetDefaultIMEWnd(HWND hWnd);
      LRESULT SendMessageA(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam);
    ]]
    )

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
      group = vim.api.nvim_create_augroup("auto_ime_windows", { clear = true }),
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
    if wsl_switch then
      return wsl_switch
    end

    local fallback = linux_switch()
    local ps_cmd = nil
    if vim.fn.executable("powershell.exe") == 1 then
      ps_cmd = "powershell.exe"
    elseif vim.fn.executable("/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe") == 1 then
      ps_cmd = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    end

    if ps_cmd then
      local job_id
      local ready, failed = false, false

      local function use_fallback()
        if fallback then
          fallback()
        end
      end

      local function send_switch()
        local ok, sent = pcall(vim.fn.chansend, job_id, "[WinIME]::ToLatin()\r\n")
        if not ok or sent <= 0 then
          failed = true
          use_fallback()
        end
      end

      job_id = vim.fn.jobstart({ ps_cmd, "-NoProfile", "-NonInteractive", "-Command", "-" }, {
        pty = false,
        stdin = "pipe",
        on_stdout = function(_, lines)
          for _, line in ipairs(lines) do
            if line:find("AUTO_IME_READY", 1, true) then
              ready = true
            elseif line:find("AUTO_IME_FAILED", 1, true) then
              failed = true
              ready = false
              if job_id then
                pcall(vim.fn.jobstop, job_id)
              end
            end
          end
        end,
        on_exit = function()
          job_id = nil
          ready = false
          failed = true
        end,
      })

      if job_id > 0 then
        local init_script = table.concat({
          "try {",
          'Add-Type -ErrorAction Stop -TypeDefinition @"',
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
          '  [Console]::Out.WriteLine("AUTO_IME_READY")',
          "} catch {",
          '  [Console]::Out.WriteLine("AUTO_IME_FAILED")',
          "}",
        }, "\r\n")

        local ok, sent = pcall(vim.fn.chansend, job_id, init_script .. "\r\n\r\n")
        if not ok or sent <= 0 then
          pcall(vim.fn.jobstop, job_id)
          return fallback
        end

        vim.defer_fn(function()
          if not ready and not failed and job_id then
            failed = true
            pcall(vim.fn.jobstop, job_id)
          end
        end, 10000)

        vim.api.nvim_create_autocmd("VimLeavePre", {
          callback = function()
            if job_id then
              pcall(vim.fn.jobstop, job_id)
            end
          end,
        })

        wsl_switch = function()
          if failed then
            return use_fallback()
          end
          if not ready then
            return
          end
          send_switch()
        end
        return wsl_switch
      end
    end

    return fallback
  end

  ------------------------------------------------
  -- Linux
  ------------------------------------------------
  if sys == "Linux" then
    return linux_switch()
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
