local real_vim = vim

local function scenario(options)
  local jobs, sends, autocmds, systems, stopped, timers, warnings = {}, {}, {}, {}, {}, {}, {}
  local fake_vim = {
    uv = {
      os_uname = function()
        return { sysname = options.sys or "Linux" }
      end,
    },
    env = options.wsl and { WSL_DISTRO_NAME = "test" } or {},
    log = { levels = { WARN = 2 } },
    notify = function(message, level)
      warnings[#warnings + 1] = { message = message, level = level }
    end,
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
        if options.send_throw_at == #sends then
          error("send failed")
        end
        if options.send_failure_at == #sends then
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
    warnings = warnings,
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
wsl.invoke(wsl.jobs[1].callbacks.on_exit)
assert(#wsl.warnings == 0, "intentional shutdown must not warn")

local failure = scenario({ wsl = true, executables = { ["powershell.exe"] = true, ibus = true } })
local fallback_switch = assert(failure.detect())
failure.invoke(fallback_switch)
failure.invoke(failure.jobs[1].callbacks.on_stdout, 17, { "AUTO_IME_FAILED" })
assert(#failure.systems == 0, "initialization failure must not switch late")
failure.invoke(fallback_switch)
assert(failure.systems[1] == "ibus engine xkb:us::eng", "subsequent switches must use fallback")
assert(failure.stopped[1] == 17, "failed worker must stop")
assert(#failure.warnings == 0, "initialization fallback must stay silent")

local exited = scenario({ wsl = true, executables = { ["powershell.exe"] = true, ibus = true } })
local exited_switch = assert(exited.detect())
exited.invoke(exited_switch)
exited.invoke(exited.jobs[1].callbacks.on_exit)
assert(#exited.systems == 0, "worker exit must not switch late")
exited.invoke(exited_switch)
assert(exited.systems[1] == "ibus engine xkb:us::eng", "worker exit must enable fallback")
assert(#exited.warnings == 0, "worker exit with fallback must stay silent")

local timed_out = scenario({ wsl = true, executables = { ["powershell.exe"] = true, ibus = true } })
local timed_out_switch = assert(timed_out.detect())
assert(timed_out.timers[1].delay == 10000, "worker initialization must be bounded")
timed_out.invoke(timed_out.timers[1].callback)
assert(timed_out.stopped[1] == 17, "timed-out worker must stop")
timed_out.invoke(timed_out_switch)
assert(timed_out.systems[1] == "ibus engine xkb:us::eng", "timeout must enable fallback")
assert(#timed_out.warnings == 0, "timeout with fallback must stay silent")

local start_failed = scenario({ wsl = true, executables = { ["powershell.exe"] = true, ibus = true }, job_result = -1 })
start_failed.invoke(assert(start_failed.detect()))
assert(start_failed.systems[1] == "ibus engine xkb:us::eng", "jobstart failure must use fallback")
assert(#start_failed.warnings == 0, "startup failure with fallback must stay silent")

local send_failed = scenario({
  wsl = true,
  executables = { ["powershell.exe"] = true, ibus = true },
  send_failure_at = 2,
})
local send_failed_switch = assert(send_failed.detect())
send_failed.invoke(send_failed.jobs[1].callbacks.on_stdout, 17, { "AUTO_IME_READY" })
send_failed.invoke(send_failed_switch)
assert(send_failed.systems[1] == "ibus engine xkb:us::eng", "active send failure must use fallback")
assert(send_failed.stopped[1] == 17, "active send failure must stop the worker")
assert(#send_failed.warnings == 0, "working fallback must stay silent")
send_failed.invoke(send_failed_switch)
send_failed.invoke(send_failed.jobs[1].callbacks.on_exit)
assert(#send_failed.sends == 2 and #send_failed.stopped == 1, "failed worker must not retry or stop twice")

local send_threw = scenario({
  wsl = true,
  executables = { ["powershell.exe"] = true },
  send_throw_at = 2,
})
local send_threw_switch = assert(send_threw.detect())
send_threw.invoke(send_threw.jobs[1].callbacks.on_stdout, 17, { "AUTO_IME_READY" })
send_threw.invoke(send_threw_switch)
send_threw.invoke(send_threw_switch)
assert(send_threw.stopped[1] == 17 and #send_threw.stopped == 1, "throwing send must retire the worker")
send_threw.invoke(send_threw.jobs[1].callbacks.on_exit)
assert(#send_threw.warnings == 1, "failed worker without fallback must warn once")
assert(send_threw.warnings[1].level == 2, "backend failure must use warning severity")

local no_fallback = scenario({ wsl = true, executables = { ["powershell.exe"] = true }, job_result = -1 })
no_fallback.detect()
no_fallback.detect()
assert(#no_fallback.warnings == 1, "startup failure without fallback must warn once across setup calls")

local init_send_failed = scenario({
  wsl = true,
  executables = { ["powershell.exe"] = true },
  send_failure_at = 1,
})
assert(init_send_failed.detect() == nil, "failed initialization cannot provide a switcher")
assert(
  init_send_failed.stopped[1] == 17 and #init_send_failed.warnings == 1,
  "failed initialization must stop and warn"
)

for _, case in ipairs({
  {
    name = "initialization error",
    trigger = function(s)
      s.invoke(s.jobs[1].callbacks.on_stdout, 17, { "AUTO_IME_FAILED" })
    end,
    stopped = 1,
  },
  {
    name = "timeout",
    trigger = function(s)
      s.invoke(s.timers[1].callback)
    end,
    stopped = 1,
  },
  {
    name = "unexpected exit",
    trigger = function(s)
      s.invoke(s.jobs[1].callbacks.on_exit)
    end,
    stopped = 0,
  },
}) do
  local s = scenario({ wsl = true, executables = { ["powershell.exe"] = true } })
  local switch_after_failure = assert(s.detect())
  s.invoke(switch_after_failure)
  case.trigger(s)
  s.invoke(s.jobs[1].callbacks.on_stdout, 17, { "AUTO_IME_READY" })
  s.invoke(switch_after_failure)
  assert(#s.sends == 1, case.name .. " must not replay or resume switching")
  assert(#s.warnings == 1 and #s.stopped == case.stopped, case.name .. " must warn once and clean up")
end

local no_ps_no_fallback = scenario({ wsl = true, executables = {} })
local no_backend_switch = assert(no_ps_no_fallback.detect())
assert(#no_ps_no_fallback.warnings == 0, "missing backend must not warn during setup")
no_ps_no_fallback.invoke(no_backend_switch)
no_ps_no_fallback.invoke(no_backend_switch)
assert(#no_ps_no_fallback.warnings == 1, "missing backend must warn once on first switch attempt")
assert(
  no_ps_no_fallback.warnings[1].message:find("no PowerShell or Linux IME tool", 1, true),
  "missing backend warning must identify the absence"
)

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
