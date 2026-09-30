local state = require("pangu.generated")
local layouts_module = require("pangu.layouts")
local session = require("pangu.session")
local primary = require("pangu.primary")

local cycle = state.layouts.cycle

local allowed = {}
for _, target in ipairs(cycle) do
  allowed[target] = true
end

local modes = session.table("layout_modes")

local rules = {}

local function apply(id, target)
  local previous = rules[id]
  if previous and previous.target == target then
    previous.rule:set_enabled(true)
    return
  end
  if previous then
    previous.rule:set_enabled(false)
  end
  rules[id] = {
    target = target,
    rule = hl.workspace_rule({
      workspace = "r[" .. id .. "-" .. id .. "]",
      layout = target,
    }),
  }
end

for id, target in pairs(modes) do
  if type(id) == "number" and id > 0 and id % 1 == 0 and allowed[target] then
    local workspace = hl.get_workspace(id)
    local is_primary = workspace and primary.workspace(workspace) or (not workspace and primary.workspace_id(id))
    if target ~= "lua:centered" or is_primary then
      apply(id, target)
    end
  else
    modes[id] = nil
  end
end

local function restore_workspace(workspace)
  if not workspace then
    return
  end
  local target = modes[workspace.id]
  if not target then
    return
  end
  if target == "lua:centered" and not primary.workspace(workspace) then
    local previous = rules[workspace.id]
    if previous then
      previous.rule:set_enabled(false)
    end
  else
    apply(workspace.id, target)
  end
  layouts_module.schedule_scan()
end

hl.on("workspace.move_to_monitor", restore_workspace)
hl.on("workspace.created", restore_workspace)

local function next_layout(current)
  for i, layout in ipairs(cycle) do
    if layout == current then
      return cycle[i % #cycle + 1]
    end
  end
  return cycle[1]
end

local M = {}

function M.set(target)
  local workspace = hl.get_active_workspace()
  if not allowed[target] or not workspace or workspace.special or workspace.tiled_layout == target then
    return
  end

  if target == "lua:centered" and not primary.workspace(workspace) then
    return
  end

  if target == "lua:centered" then
    layouts_module.center_active()
  end

  apply(workspace.id, target)
  modes[workspace.id] = target
  session.save()

  layouts_module.schedule_scan()
end

function M.toggle()
  local workspace = hl.get_active_workspace()
  if not workspace or workspace.special then
    return
  end
  local target = workspace.tiled_layout
  for _ = 1, #cycle do
    target = next_layout(target)
    if target ~= "lua:centered" or primary.workspace(workspace) then
      M.set(target)
      return
    end
  end
end

return M
