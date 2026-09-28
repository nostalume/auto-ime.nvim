local real_vim = vim
local loaded = {}
for _, name in ipairs({ "auto-ime", "auto-ime.core", "auto-ime.platforms", "ffi" }) do
  loaded[name] = { value = package.loaded[name] }
  package.loaded[name] = nil
end

local autocmds = {}
local foreground = 1
local ime_windows = { [1] = 2, [3] = 4 }
local messages = {}
local ffi = {
  NULL = {},
  cdef = function() end,
  load = function(name)
    if name == "user32" then
      return {
        GetForegroundWindow = function()
          return foreground
        end,
        SendMessageA = function(hwnd, _, command)
          messages[#messages + 1] = { hwnd = hwnd, command = command }
          return (command == 1 or command == 5) and 1 or 0
        end,
      }
    end
    return {
      ImmGetDefaultIMEWnd = function(hwnd)
        return ime_windows[hwnd]
      end,
    }
  end,
}
package.loaded.ffi = ffi

_G.vim = {
  uv = {
    os_uname = function()
      return { sysname = "Windows_NT" }
    end,
  },
  env = {},
  fn = {
    has = function()
      return 1
    end,
  },
  api = {
    nvim_create_augroup = function(name, options)
      if options.clear then
        for index = #autocmds, 1, -1 do
          if autocmds[index].group == name then
            table.remove(autocmds, index)
          end
        end
      end
      return name
    end,
    nvim_create_autocmd = function(events, options)
      if type(events) == "string" then
        events = { events }
      end
      for _, event in ipairs(events) do
        autocmds[#autocmds + 1] = { event = event, group = options.group, callback = options.callback }
      end
    end,
  },
}

package.loaded["auto-ime.platforms"] = assert(loadfile("lua/auto-ime/platforms.lua"))()
package.loaded["auto-ime.core"] = assert(loadfile("lua/auto-ime/core.lua"))()
local plugin = assert(loadfile("lua/auto-ime/init.lua"))()
plugin.setup()
plugin.setup()

local function count(event)
  local result = 0
  for _, autocmd in ipairs(autocmds) do
    if autocmd.event == event then
      result = result + 1
    end
  end
  return result
end

assert(count("InsertEnter") == 0, "fresh target selection must not require an InsertEnter handler")
assert(count("InsertLeave") == 1, "repeated setup must register one InsertLeave handler")
assert(count("CmdlineLeave") == 1, "repeated setup must register one CmdlineLeave handler")

local function switch(event)
  for _, autocmd in ipairs(autocmds) do
    if autocmd.event == (event or "InsertLeave") then
      autocmd.callback()
      return
    end
  end
  error("missing " .. (event or "InsertLeave") .. " handler")
end

switch()
assert(#messages == 4 and messages[1].hwnd == 2, "fresh IME target must receive both mode updates")
foreground = nil
switch()
assert(#messages == 4, "null foreground must not reuse a previous IME target")
foreground = ffi.NULL
switch()
assert(#messages == 4, "null HWND must not reuse a previous IME target")
foreground = 3
switch("CmdlineLeave")
assert(#messages == 8 and messages[5].hwnd == 4, "changed foreground must use its fresh IME target")
ime_windows[3] = ffi.NULL
switch()
assert(#messages == 8, "null IME HWND must not reuse a previous target")
foreground = 5
switch()
assert(#messages == 8, "missing IME target must not reuse a previous target")

_G.vim = real_vim
for name, entry in pairs(loaded) do
  package.loaded[name] = entry.value
end
print("setup scenarios passed")
