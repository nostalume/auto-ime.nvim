local real_vim = vim

local function scenario(options)
  local jobs, sends, autocmds, systems, stopped, timers = {}, {}, {}, {}, {}, {}
  local fake_vim = {
    uv = {
      os_uname = function()
        return { sysname = options.sys or "Linux" }
      end,
    },
    env = options.wsl and { WSL_DISTRO_NAME = "test" } or {},
    fn = {
      has = function()
        return 0
      end,
      executable = function(name)
        return options.executables[name] and 1 or 0
      end,
      system = function(command)
        systems[#systems + 1] = command
        return command == "fcitx5-remote" and "2" or ""
      end,
      jobstart = function(command, callbacks)
        jobs[#jobs + 1] = { command = command, callbacks = callbacks }
        return options.job_result or 17
      end,
      chansend = function(_, value)
        sends[#sends + 1] = value
        if options.send_failure then
          return 0
        end
        return #value
      end,
      jobstop = function(id)
        stopped[#stopped + 1] = id
      end,
    },
    api = {
      nvim_create_autocmd = function(event, spec)
        autocmds[event] = spec.callback
      end,
    },
    defer_fn = function(callback, delay)
      timers[#timers + 1] = { callback = callback, delay = delay }
    end,
  }

  _G.vim = fake_vim
  local platform = assert(loadfile("lua/auto-ime/platforms.lua"))()
  _G.vim = real_vim

  return {
    detect = function()
      _G.vim = fake_vim
      local result = platform.detect()
      _G.vim = real_vim
      return result
    end,
    invoke = function(callback, ...)
      _G.vim = fake_vim
      callback(...)
      _G.vim = real_vim
    end,
    jobs = jobs,
    sends = sends,
    autocmds = autocmds,
    systems = systems,
    stopped = stopped,
    timers = timers,
  }
end

local wsl = scenario({ wsl = true, executables = { ["powershell.exe"] = true } })
local switch = assert(wsl.detect())
assert(wsl.detect() == switch and #wsl.jobs == 1, "setup must not spawn another PowerShell")
assert(wsl.sends[1]:find("Add-Type -ErrorAction Stop", 1, true), "worker must initialize")
wsl.invoke(switch)
assert(#wsl.sends == 1, "do not switch before worker initialization")
wsl.invoke(wsl.jobs[1].callbacks.on_stdout, 17, { "AUTO_IME_READY" })
assert(#wsl.sends == 1, "startup must not switch late after the user may have changed focus")
wsl.invoke(switch)
assert(#wsl.sends == 2 and wsl.sends[2]:find("ToLatin", 1, true), "ready worker must accept later switches")
wsl.invoke(wsl.autocmds.VimLeavePre)
assert(wsl.stopped[1] == 17, "worker must stop on exit")

local failure = scenario({ wsl = true, executables = { ["powershell.exe"] = true, ibus = true } })
local fallback_switch = assert(failure.detect())
failure.invoke(fallback_switch)
failure.invoke(failure.jobs[1].callbacks.on_stdout, 17, { "AUTO_IME_FAILED" })
assert(#failure.systems == 0, "initialization failure must not switch late")
failure.invoke(fallback_switch)
assert(failure.systems[1] == "ibus engine xkb:us::eng", "subsequent switches must use fallback")
assert(failure.stopped[1] == 17, "failed worker must stop")

local exited = scenario({ wsl = true, executables = { ["powershell.exe"] = true, ibus = true } })
local exited_switch = assert(exited.detect())
exited.invoke(exited_switch)
exited.invoke(exited.jobs[1].callbacks.on_exit)
assert(#exited.systems == 0, "worker exit must not switch late")
exited.invoke(exited_switch)
assert(exited.systems[1] == "ibus engine xkb:us::eng", "worker exit must enable fallback")

local timed_out = scenario({ wsl = true, executables = { ["powershell.exe"] = true, ibus = true } })
local timed_out_switch = assert(timed_out.detect())
assert(timed_out.timers[1].delay == 10000, "worker initialization must be bounded")
timed_out.invoke(timed_out.timers[1].callback)
assert(timed_out.stopped[1] == 17, "timed-out worker must stop")
timed_out.invoke(timed_out_switch)
assert(timed_out.systems[1] == "ibus engine xkb:us::eng", "timeout must enable fallback")

local start_failed = scenario({ wsl = true, executables = { ["powershell.exe"] = true, ibus = true }, job_result = -1 })
start_failed.invoke(assert(start_failed.detect()))
assert(start_failed.systems[1] == "ibus engine xkb:us::eng", "jobstart failure must use fallback")

local no_ps = scenario({ wsl = true, executables = { ["fcitx5-remote"] = true } })
no_ps.invoke(assert(no_ps.detect()))
assert(no_ps.systems[1] == "fcitx5-remote" and no_ps.systems[2] == "fcitx5-remote -c")

local linux = scenario({ wsl = false, executables = { ibus = true } })
linux.invoke(assert(linux.detect()))
assert(linux.systems[1] == "ibus engine xkb:us::eng", "native Linux behavior must remain intact")

local mac = scenario({ sys = "Darwin", executables = { macism = true } })
mac.invoke(assert(mac.detect()))
assert(mac.systems[1] == "macism com.apple.keylayout.ABC", "macOS command must be selected")

if os.getenv("AUTO_IME_TEST_POWERSHELL") == "1" then
  local output, errors = {}, {}
  local id = real_vim.fn.jobstart(wsl.jobs[1].command, {
    stdin = "pipe",
    on_stdout = function(_, lines)
      for _, line in ipairs(lines) do
        output[#output + 1] = line
      end
    end,
    on_stderr = function(_, lines)
      for _, line in ipairs(lines) do
        errors[#errors + 1] = line
      end
    end,
  })
  assert(id > 0, "could not start PowerShell")
  assert(real_vim.fn.chansend(id, wsl.sends[1]) > 0, "could not send PowerShell script")
  real_vim.wait(10000, function()
    return #output > 0 or #errors > 0
  end, 10)
  assert(
    table.concat(output, "\n"):find("AUTO_IME_READY", 1, true),
    "PowerShell initialization failed: " .. table.concat(output, "\n") .. " / " .. table.concat(errors, "\n")
  )
  real_vim.fn.chansend(id, "Write-Output 43\r\n")
  real_vim.wait(5000, function()
    return table.concat(output, "\n"):find("43", 1, true) ~= nil
  end, 10)
  real_vim.fn.chanclose(id, "stdin")
  assert(real_vim.fn.jobwait({ id }, 20000)[1] == 0, "PowerShell initialization did not finish")
  assert(table.concat(output, "\n"):find("43", 1, true), "PowerShell did not accept a later command")
end

print("platform scenarios passed")
