require("pangu.shell")
require("pangu.shell_rules")
require("pangu.gamemode")

local data = os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")
local chunk = loadfile(data .. "/pangu/macros.lua")
if chunk then
  local ok, err = pcall(chunk)
  if not ok then
    io.stderr:write("pangu: failed to apply macros.lua: " .. tostring(err) .. "\n")
  end
end

return true
