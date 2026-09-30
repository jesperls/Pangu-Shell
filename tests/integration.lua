local source = assert(arg[1])
table.insert(package.searchers, 2, function(name)
  local file = name:match("^pangu%.(.+)$")
  if file then return assert(loadfile(source .. "/" .. file .. ".lua")) end
end)
package.preload["pangu.generated"] = function() return { shell = true } end

local loaded, timers, rules, binds = {}, 0, {}, {}
local original_loadfile = loadfile
loadfile = function(path, ...)
  if path:match("/pangu/hyprland.lua$") then
    return function() loaded.theme = true end
  elseif path:match("/pangu/macros.lua$") then
    return function() loaded.macros = true end
  end
  return original_loadfile(path, ...)
end
hl = {
  timer = function() timers = timers + 1 end,
  window_rule = function(rule) rules[#rules + 1] = rule end,
  bind = function(combo, dispatcher) binds[combo] = dispatcher end,
  dsp = { exec_cmd = function(command) return command end },
}
require("pangu.integration")
assert(loaded.theme and loaded.macros, "Standalone integration must load generated theme and macro hooks")
assert(timers == 1, "Standalone integration must monitor game-mode state")
assert(#rules == 2, "Standalone integration must position the shell windows")
assert(not package.loaded["pangu.settings"], "Standalone integration changed desktop preferences")
assert(not package.loaded["pangu.binds"], "Standalone integration loaded desktop keybindings")
require("pangu.bindings")
assert(binds["SUPER + I"] == "pangu run settings")
assert(binds["SUPER + L"] == "pangu run lockscreen")
loadfile = original_loadfile
print("Standalone theme, macro, game-mode, window and shortcut integration passed")
