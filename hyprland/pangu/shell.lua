local state = require("pangu.generated")

if not state.shell then
  return true
end

local data = os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")

local chunk = loadfile(data .. "/pangu/hyprland.lua")
if chunk then
  local ok, err = pcall(chunk)
  if not ok then
    io.stderr:write("pangu: failed to apply " .. data .. "/pangu/hyprland.lua: " .. tostring(err) .. "\n")
  end
end

return true
