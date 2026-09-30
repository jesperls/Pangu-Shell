local state = require("pangu.generated")

local by_id = {}
for _, id in ipairs(state.monitors.primary_workspaces or {}) do
  by_id[id] = true
end

local M = {}

function M.monitor(monitor)
  local name = state.monitors.primary
  if not monitor then
    return false
  end
  if not name then
    local monitors = hl.get_monitors()
    return monitors[1] and monitor.name == monitors[1].name or false
  end
  if name:sub(1, 5) == "desc:" then
    return monitor.description == name:sub(6)
  end
  return monitor.name == name
end

function M.workspace(workspace)
  if not workspace then
    return false
  end
  if workspace.monitor then
    return M.monitor(workspace.monitor)
  end
  return by_id[workspace.id] == true
end

function M.workspace_id(id)
  return by_id[id] == true
end

return M
