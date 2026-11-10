local state = require("pangu.generated")

local by_id = {}
for _, id in ipairs(state.monitors.primary_workspaces or {}) do
  by_id[id] = true
end

local cached_primary_name = nil

local M = {}

function M.monitor(monitor)
  local name = state.monitors.primary
  if not monitor then
    return false
  end
  if not name then
    if not cached_primary_name then
      local monitors = hl.get_monitors()
      if monitors[1] then
        cached_primary_name = monitors[1].name
      end
    end
    return cached_primary_name ~= nil and monitor.name == cached_primary_name
  end
  if name:sub(1, 5) == "desc:" then
    local pat = name:sub(6)
    local desc = tostring(monitor.description or "")
    return desc == pat or desc:sub(1, #pat) == pat
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
