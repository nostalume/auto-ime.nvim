local M = {}
local wsl_switch
local wsl_warned = false

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

    return function()
      local win = user32.GetForegroundWindow()
      if win == nil or win == ffi.NULL then
        return
      end
      local ime_hwnd = imm32.ImmGetDefaultIMEWnd(win)
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
    local function warn_no_backend(reason)
      if not wsl_warned then
        wsl_warned = true
        vim.notify("auto-ime: WSL IME switching unavailable: " .. reason, vim.log.levels.WARN)
      end
    end

    local ps_cmd
    if vim.fn.executable("powershell.exe") == 1 then
      ps_cmd = "powershell.exe"
    elseif vim.fn.executable("/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe") == 1 then
      ps_cmd = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    end
    if not ps_cmd then
      return fallback or function()
        warn_no_backend("no PowerShell or Linux IME tool")
      end
    end

    local job_id
    local ready, failed = false, false
    local function stop_worker()
      local id = job_id
      job_id = nil
      if id and id > 0 then
        pcall(vim.fn.jobstop, id)
      end
    end
    local function fail_worker()
      if failed then
        return
      end
      failed, ready = true, false
      stop_worker()
      if not fallback then
        warn_no_backend("PowerShell worker failed")
      end
    end

    job_id = vim.fn.jobstart({ ps_cmd, "-NoProfile", "-NonInteractive", "-Command", "-" }, {
      pty = false,
      stdin = "pipe",
      on_stdout = function(_, lines)
        for _, line in ipairs(lines) do
          if line:find("AUTO_IME_FAILED", 1, true) then
            fail_worker()
          elseif line:find("AUTO_IME_READY", 1, true) and not failed then
            ready = true
          end
        end
      end,
      on_exit = function()
        job_id = nil
        fail_worker()
      end,
    })
    if job_id <= 0 then
      fail_worker()
      return fallback
    end

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
      fail_worker()
      return fallback
    end

    vim.defer_fn(function()
      if not ready and not failed and job_id then
        fail_worker()
      end
    end, 10000)

    vim.api.nvim_create_autocmd("VimLeavePre", {
      callback = function()
        failed, ready = true, false
        stop_worker()
      end,
    })

    wsl_switch = function()
      if failed then
        if fallback then
          return fallback()
        end
        return
      end
      if not ready then
        return
      end
      local ok, sent = pcall(vim.fn.chansend, job_id, "[WinIME]::ToLatin()\r\n")
      if not ok or sent <= 0 then
        fail_worker()
        if fallback then
          fallback()
        end
      end
    end
    return wsl_switch
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
