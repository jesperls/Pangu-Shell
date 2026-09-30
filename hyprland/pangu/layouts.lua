local state = require("pangu.generated")
local gamemode = require("pangu.gamemode")
local session = require("pangu.session")

local mwfact = state.layouts.centered.master_width
local full_height = state.layouts.centered.full_height
local aspect = state.layouts.centered.aspect[1] / state.layouts.centered.aspect[2]

local slots = session.table("slots")
local weights = session.table("weights")
local fresh = {}

local function stack(entries, box)
  local total = 0
  for _, entry in ipairs(entries) do
    total = total + entry.weight
  end
  local y = box.y
  for i, entry in ipairs(entries) do
    local h = box.h * entry.weight / total
    if i == #entries then
      h = box.y + box.h - y
    end
    entry.target:place({ x = box.x, y = y, w = box.w, h = h })
    y = y + h
  end
end

local function workspace_id(ctx)
  for _, target in ipairs(ctx.targets) do
    local window = target.window
    if window and window.workspace then
      return window.workspace.id
    end
  end
  return 0
end

local function lighter(s)
  return #s.right <= #s.left and s.right or s.left
end

local function index_of(list, id)
  for i, v in ipairs(list) do
    if v == id then
      return i
    end
  end
end

local function insert_by_y(list, id, cy, area)
  local n = #list + 1
  local index = math.floor((cy - area.y) / (area.h / n)) + 1
  table.insert(list, math.min(math.max(index, 1), n), id)
end

local function active_id(ctx)
  for _, target in ipairs(ctx.targets) do
    if target.window and target.window.active then
      return target.window.stable_id
    end
  end
end

hl.on("window.open_early", function(window)
  if window then
    fresh[window.stable_id] = true
  end
end)

hl.on("window.close", function(window)
  if not window then
    return
  end
  local id = window.stable_id
  fresh[id] = nil
  weights[id] = nil
  for _, s in pairs(slots) do
    if s.master == id then
      s.master = table.remove(s.right, 1) or table.remove(s.left, 1)
    else
      for _, list in ipairs({ s.left, s.right }) do
        local i = index_of(list, id)
        if i then
          table.remove(list, i)
          break
        end
      end
    end
  end
end)

local function classify(s, id, target, area, master_w)
  local box = target.box
  local cx = box.x + box.w / 2
  local cy = box.y + box.h / 2
  local master_x = area.x + (area.w - master_w) / 2

  if cx < master_x then
    insert_by_y(s.left, id, cy, area)
  elseif cx > master_x + master_w then
    insert_by_y(s.right, id, cy, area)
  else
    if s.master then
      table.insert(lighter(s), 1, s.master)
    end
    s.master = id
  end
end

local promote_pending = {}

local function seed(s, ctx, area)
  local active = active_id(ctx)
  for _, target in ipairs(ctx.targets) do
    local id = target.window and target.window.stable_id
    if id then
      fresh[id] = nil
      if id == active then
        s.master = id
      else
        local box = target.box
        local list = box.x + box.w / 2 < area.x + area.w / 2 and s.left or s.right
        insert_by_y(list, id, box.y + box.h / 2, area)
      end
    end
  end
  if not s.master then
    s.master = table.remove(s.right, 1) or table.remove(s.left, 1)
  end
end

local function sync(ctx, area, master_w)
  local ws = workspace_id(ctx)
  local s = slots[ws]

  local present = {}
  for _, target in ipairs(ctx.targets) do
    if target.window then
      present[target.window.stable_id] = target
    end
  end

  if not s then
    s = { master = nil, left = {}, right = {} }
    slots[ws] = s
    promote_pending[ws] = nil
    seed(s, ctx, area)
    return s, present
  end

  local alive = {}
  for _, window in ipairs(hl.get_workspace_windows(ws)) do
    if not window.floating then
      alive[window.stable_id] = true
    end
  end

  for _, list in ipairs({ s.left, s.right }) do
    for i = #list, 1, -1 do
      if not alive[list[i]] then
        table.remove(list, i)
      end
    end
  end
  if s.master and not alive[s.master] then
    s.master = table.remove(s.right, 1) or table.remove(s.left, 1)
  end

  local known = {}
  if s.master then
    known[s.master] = true
  end
  for _, list in ipairs({ s.left, s.right }) do
    for _, id in ipairs(list) do
      known[id] = true
    end
  end

  for _, target in ipairs(ctx.targets) do
    local id = target.window and target.window.stable_id
    if id and not known[id] then
      if not s.master then
        s.master = id
      elseif fresh[id] then
        table.insert(lighter(s), id)
      else
        classify(s, id, target, area, master_w)
      end
      fresh[id] = nil
    end
  end

  if promote_pending[ws] then
    promote_pending[ws] = nil
    local id = active_id(ctx)
    if id and id ~= s.master then
      for _, list in ipairs({ s.left, s.right }) do
        local i = index_of(list, id)
        if i then
          list[i] = s.master
          s.master = id
          break
        end
      end
    end
  end

  return s, present
end

local function monitor_box(mon)
  local w, h = mon.width, mon.height
  if mon.transform % 2 == 1 then
    w, h = h, w
  end
  local scale = mon.scale or 1
  return { x = mon.x, y = mon.y, w = w / scale, h = h / scale }
end

local function full_master_box(mon)
  local box = monitor_box(mon)
  local w = box.h * aspect
  if w >= box.w then
    return nil
  end
  return { x = box.x + (box.w - w) / 2, y = box.y, w = w, h = box.h }
end

local emitted = {}

local function update_gap(mon)
  local master = full_master_box(mon)
  local ws = mon.active_workspace
  local on = master ~= nil
  if on then
    on = ws ~= nil and not ws.special and ws.tiled_layout == "lua:centered"
    if on then
      on = false
      for _, window in ipairs(hl.get_workspace_windows(ws.id)) do
        if not window.floating then
          on = true
          break
        end
      end
    end
  end

  local payload
  if on then
    local box = monitor_box(mon)
    local square = gamemode.is_active(ws.id) and 1 or 0
    payload = string.format(
      "centergap,%s,%d,%d,%d",
      mon.name,
      math.floor(master.x - box.x + 0.5),
      math.floor(master.w + 0.5),
      square
    )
  else
    payload = string.format("centergap,%s,0,0,0", mon.name)
  end
  if emitted[mon.name] ~= payload then
    emitted[mon.name] = payload
    hl.dispatch(hl.dsp.event(payload))
  end
end

local function prune_session()
  local live_ws = {}
  local live_windows = {}
  for _, ws in ipairs(hl.get_workspaces()) do
    live_ws[ws.id] = true
    for _, window in ipairs(hl.get_workspace_windows(ws.id)) do
      live_windows[window.stable_id] = true
    end
  end

  for id in pairs(slots) do
    if not live_ws[id] then
      slots[id] = nil
    end
  end
  for id in pairs(weights) do
    if not live_windows[id] then
      weights[id] = nil
    end
  end
end

local function scan()
  if full_height then
    for _, mon in ipairs(hl.get_monitors()) do
      update_gap(mon)
    end
  end
  prune_session()
  session.save()
end

local scan_timer

-- Deferred so window/workspace teardown has settled before we re-check.
local function schedule_scan()
  if scan_timer then
    scan_timer:set_enabled(true)
  else
    scan_timer = hl.timer(function()
      scan_timer:set_enabled(false)
      scan()
    end, { timeout = 30, type = "repeat" })
  end
end

for _, event in ipairs({
  "workspace.active",
  "workspace.move_to_monitor",
  "window.open",
  "window.close",
  "window.move_to_workspace",
  "monitor.added",
  "monitor.removed",
  "monitor.layout_changed",
}) do
  hl.on(event, schedule_scan)
end

if full_height then
  hl.on("layer.opened", function()
    emitted = {}
    schedule_scan()
  end)
end

hl.on("config.reloaded", schedule_scan)
schedule_scan()

gamemode.on_change(schedule_scan)

local function ctx_monitor(ctx)
  for _, target in ipairs(ctx.targets) do
    local window = target.window
    if window and window.workspace and window.workspace.monitor then
      return window.workspace.monitor
    end
  end
end

local drag = nil

local function drag_apply(ctx, s, _, ddy)
  local area = ctx.area
  local id = drag.id

  local list = (index_of(s.left, id) and s.left) or (index_of(s.right, id) and s.right)
  if not list then
    return
  end

  local i = index_of(list, id)
  local above, below
  if drag.grab_top then
    above, below = list[i - 1], list[i]
  else
    above, below = list[i], list[i + 1]
  end
  if not (above and below) then
    return
  end

  local total = 0
  for _, wid in ipairs(list) do
    total = total + (weights[wid] or 1)
  end
  local wa = weights[above] or 1
  local wb = weights[below] or 1
  local dw = ddy / area.h * total
  dw = math.max(0.15 - wa, math.min(wb - 0.15, dw))
  weights[above], weights[below] = wa + dw, wb - dw
end

local drag_timer = nil

local function drag_tick()
  if not drag then
    return
  end
  local workspace = hl.get_active_workspace()
  if not workspace or workspace.tiled_layout ~= "lua:centered" then
    drag = nil
    if drag_timer then
      drag_timer:set_enabled(false)
    end
    return
  end
  if drag.super and not (hl.is_key_down("Super_L") or hl.is_key_down("Super_R")) then
    drag = nil
    drag_timer:set_enabled(false)
    return
  end
  local pos = hl.get_cursor_pos()
  if not pos then
    return
  end
  local dx, dy = pos.x - drag.x, pos.y - drag.y
  if dx == 0 and dy == 0 then
    return
  end
  drag.x, drag.y = pos.x, pos.y
  hl.dispatch(hl.dsp.layout(string.format("dragresize %.2f %.2f", dx, dy)))
end

local M = {}

M.schedule_scan = schedule_scan

function M.center_active()
  local workspace = hl.get_active_workspace()
  if workspace then
    promote_pending[workspace.id] = true
  end
end

function M.master_focused()
  local window = hl.get_active_window()
  local workspace = hl.get_active_workspace()
  if not window or window.floating or not workspace then
    return false
  end
  local s = slots[workspace.id]
  return s ~= nil and s.master == window.stable_id
end

function M.start_drag()
  local window = hl.get_active_window()
  local workspace = hl.get_active_workspace()
  if not window or window.floating or not workspace or workspace.tiled_layout ~= "lua:centered" then
    return
  end
  local s = slots[workspace.id]
  if s and s.master == window.stable_id then
    return
  end
  local pos = hl.get_cursor_pos()
  if not pos then
    return
  end

  local at, size = window.at, window.size
  drag = {
    id = window.stable_id,
    x = pos.x,
    y = pos.y,
    grab_top = at and size and pos.y < at.y + size.y / 2 or false,
    super = hl.is_key_down("Super_L") or hl.is_key_down("Super_R"),
  }

  if drag_timer then
    drag_timer:set_enabled(true)
  else
    drag_timer = hl.timer(drag_tick, { timeout = 16, type = "repeat" })
  end
end

function M.end_drag()
  drag = nil
  if drag_timer then
    drag_timer:set_enabled(false)
  end
end


hl.layout.register("centered", {
  recalculate = function(ctx)
    schedule_scan()
    local n = #ctx.targets
    if n == 0 then
      return
    end

    local area = ctx.area
    local master_w = area.w * mwfact
    local master_box
    if full_height then
      local mon = ctx_monitor(ctx)
      master_box = mon and full_master_box(mon)
      if master_box then
        master_w = master_box.w
      end
    end
    local s, present = sync(ctx, area, master_w)

    if n == 1 then
      ctx.targets[1]:place(master_box or { x = area.x + (area.w - master_w) / 2, y = area.y, w = master_w, h = area.h })
      return
    end

    local function side_entries(ids)
      local entries = {}
      for _, id in ipairs(ids) do
        if present[id] then
          table.insert(entries, { target = present[id], weight = weights[id] or 1 })
        end
      end
      return entries
    end

    local left = side_entries(s.left)
    local right = side_entries(s.right)
    for _, target in ipairs(ctx.targets) do
      if not target.window then
        table.insert(#right <= #left and right or left, { target = target, weight = 1 })
      end
    end

    local master_x = master_box and master_box.x or (area.x + (area.w - master_w) / 2)
    local master = s.master and present[s.master] or nil
    if not master then
      local entry = table.remove(right, 1) or table.remove(left, 1)
      master = entry and entry.target or ctx.targets[1]
    end
    master:place(master_box or { x = master_x, y = area.y, w = master_w, h = area.h })

    if #right > 0 then
      local right_x = master_x + master_w
      stack(right, { x = right_x, y = area.y, w = area.x + area.w - right_x, h = area.h })
    end
    if #left > 0 then
      stack(left, { x = area.x, y = area.y, w = master_x - area.x, h = area.h })
    end
  end,

  layout_msg = function(ctx, msg)
    local s = slots[workspace_id(ctx)]
    if not s then
      return
    end

    if msg == "promote" then
      local id = active_id(ctx)
      if not id or id == s.master then
        return true
      end
      for _, list in ipairs({ s.left, s.right }) do
        local i = index_of(list, id)
        if i then
          list[i] = s.master
          s.master = id
          return true
        end
      end
      return true
    end

    local dir = msg:match("^move%s+([lrud])$")
    if dir then
      local id = active_id(ctx)
      if not id then
        return true
      end

      if dir == "u" or dir == "d" then
        for _, list in ipairs({ s.left, s.right }) do
          local i = index_of(list, id)
          if i then
            local j = dir == "u" and i - 1 or i + 1
            if list[j] then
              list[i], list[j] = list[j], list[i]
            end
            return true
          end
        end
        return true
      end

      if id == s.master then
        local list = dir == "l" and s.left or s.right
        if list[1] then
          s.master = list[1]
          list[1] = id
        end
        return true
      end

      local toward_center = (dir == "r" and index_of(s.left, id)) or (dir == "l" and index_of(s.right, id))
      if toward_center then
        local list = dir == "r" and s.left or s.right
        list[toward_center] = s.master
        s.master = id
      end
      return true
    end

    local ddx, ddy = msg:match("^dragresize%s+([-%d.]+)%s+([-%d.]+)$")
    if ddx then
      if drag then
        drag_apply(ctx, s, tonumber(ddx), tonumber(ddy))
      end
      return true
    end

    local delta = msg:match("^vresize%s+([+-]?%d*%.?%d+)$")
    if delta then
      local id = active_id(ctx)
      if id and id ~= s.master then
        weights[id] = math.min(4, math.max(0.25, (weights[id] or 1) + tonumber(delta)))
      end
      return true
    end

    if msg == "equalize" then
      if s.master then weights[s.master] = nil end
      for _, list in ipairs({ s.left, s.right }) do
        for _, id in ipairs(list) do
          weights[id] = nil
        end
      end
      return true
    end
  end,
})

return M
