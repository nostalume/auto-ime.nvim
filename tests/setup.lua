local real_vim = vim
local loaded = {}
for _, name in ipairs({ "auto-ime", "auto-ime.core", "auto-ime.platforms", "ffi" }) do
  loaded[name] = { value = package.loaded[name] }
  package.loaded[name] = nil
end

local autocmds = {}
local ffi = {
  NULL = {},
  cdef = function() end,
  load = function(name)
    if name == "user32" then
      return {
        GetForegroundWindow = function()
          return 1
        end,
        SendMessageA = function()
          return 0
        end,
      }
    end
    return {
      ImmGetDefaultIMEWnd = function()
        return 2
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

assert(count("InsertEnter") == 1, "repeated setup must register one Windows InsertEnter handler")
assert(count("InsertLeave") == 1, "repeated setup must register one InsertLeave handler")
assert(count("CmdlineLeave") == 1, "repeated setup must register one CmdlineLeave handler")

_G.vim = real_vim
for name, entry in pairs(loaded) do
  package.loaded[name] = entry.value
end
print("setup scenarios passed")
