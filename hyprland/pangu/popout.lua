local ok_state, state = pcall(require, "pangu.generated")
local default_scratchpad = ok_state and state and state.scratchpad or nil

local SIZE = { x = 640, y = 360 }
local MARGIN = 20
local TILED_TAG = "popout_was_tiled"
local SCRATCHPAD_TILED_TAG = "scratchpad_was_tiled"
local HOME_PREFIX = "popout_from_"

local M = {
  scratchpad_size = {
    x = default_scratchpad and default_scratchpad.width or 900,
    y = default_scratchpad and default_scratchpad.height or 700,
  },
}

local saved_geometries = {}

local function win_key(window)
  return window.stable_id or window.address
end

local function tag_list(window)
  local tags = window.tags
  if type(tags) == "table" then
    return tags
  end
  if type(tags) == "string" then
    return { tags }
  end
  return {}
end

local function has_tag(window, name)
  for _, tag in pairs(tag_list(window)) do
    if tostring(tag) == name then
      return true
    end
  end
  return false
end

local function origin(window)
  for _, tag in pairs(tag_list(window)) do
    local home = tostring(tag):match("^" .. HOME_PREFIX .. "(.+)$")
    if home then
      return home
    end
  end
end

local function is_special(ws)
  return ws ~= nil
    and (ws.special == true or (ws.id ~= nil and ws.id < 0) or tostring(ws.name or ""):sub(1, 8) == "special:")
end

local function monitor_work_area(monitor)
  if not monitor then
    return nil
  end
  local width, height = monitor.width, monitor.height
  if (monitor.transform or 0) % 2 == 1 then
    width, height = height, width
  end
  local scale = monitor.scale or 1
  local w = math.floor(width / scale)
  local h = math.floor(height / scale)
  local r = type(monitor.reserved) == "table" and monitor.reserved or {}
  local left = r.left or r[1] or 0
  local top = r.top or r[2] or 0
  local right = r.right or r[3] or 0
  local bottom = r.bottom or r[4] or 0
  return {
    x = (monitor.x or 0) + left,
    y = (monitor.y or 0) + top,
    w = math.max(100, w - left - right),
    h = math.max(100, h - top - bottom),
  }
end

local function clamped_centered_geometry(area, target_w, target_h)
  local max_w = math.max(100, area.w - 2 * MARGIN)
  local max_h = math.max(100, area.h - 2 * MARGIN)
  local w = math.min(target_w, max_w)
  local h = math.min(target_h, max_h)
  local x = area.x + math.floor((area.w - w) / 2)
  local y = area.y + math.floor((area.h - h) / 2)
  return x, y, w, h
end

function M.clamp_to_monitor(window, monitor)
  monitor = monitor or (window and window.monitor) or hl.get_active_monitor()
  local area = monitor_work_area(monitor)
  if not window or not area then
    return
  end
  local cur_size = type(window.size) == "table" and window.size or {}
  local cur_at = type(window.at) == "table" and window.at or {}
  local max_w = math.max(100, area.w - 2 * MARGIN)
  local max_h = math.max(100, area.h - 2 * MARGIN)
  local cur_w = cur_size.x or M.scratchpad_size.x
  local cur_h = cur_size.y or M.scratchpad_size.y
  local w = math.min(cur_w, max_w)
  local h = math.min(cur_h, max_h)

  if w ~= cur_w or h ~= cur_h then
    hl.dispatch(hl.dsp.window.resize({ x = w, y = h, window = window }))
  end

  local x = cur_at.x
  local y = cur_at.y
  local out_of_bounds = x == nil
    or y == nil
    or x < area.x
    or y < area.y
    or x + w > area.x + area.w
    or y + h > area.y + area.h

  if out_of_bounds then
    hl.dispatch(hl.dsp.window.move({
      x = area.x + math.floor((area.w - w) / 2),
      y = area.y + math.floor((area.h - h) / 2),
      window = window,
    }))
  end
end

if hl.on then
  hl.on("window.close", function(window)
    if window then
      saved_geometries[win_key(window)] = nil
    end
  end)
end

local function pin(window)
  local workspace = window.workspace
  local monitor = (workspace and workspace.monitor) or window.monitor or hl.get_active_monitor()
  local home

  if is_special(workspace) then
    home = tostring(workspace.name or ""):match("^special:(.+)$")
    if home then
      hl.dispatch(hl.dsp.window.tag({ tag = "+" .. HOME_PREFIX .. home, window = window }))
    end
  end

  hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 0, window = window })) -- float/pin refuse fullscreen windows

  if window.floating and not home then
    local at = type(window.at) == "table" and window.at or nil
    local sz = type(window.size) == "table" and window.size or nil
    if at and sz and at.x and at.y and sz.x and sz.y then
      saved_geometries[win_key(window)] = {
        at = { x = at.x, y = at.y },
        size = { x = sz.x, y = sz.y },
      }
    end
  elseif not window.floating then
    saved_geometries[win_key(window)] = nil
    hl.dispatch(hl.dsp.window.tag({ tag = "+" .. TILED_TAG, window = window }))
    hl.dispatch(hl.dsp.window.float({ action = "enable", window = window }))
  end

  hl.dispatch(hl.dsp.window.pin({ action = "enable", window = window }))
  hl.dispatch(hl.dsp.window.resize({ x = SIZE.x, y = SIZE.y, window = window }))

  local area = monitor_work_area(monitor)
  if area then
    hl.dispatch(hl.dsp.window.move({
      x = area.x + area.w - SIZE.x - MARGIN,
      y = area.y + area.h - SIZE.y - MARGIN,
      window = window,
    }))
  end

  if home and monitor and monitor.active_special_workspace then
    if monitor.active_special_workspace.name == "special:" .. home then
      hl.dispatch(hl.dsp.workspace.toggle_special(home))
    end
  end
end

local function unpin(window)
  hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 0, window = window })) -- unpin refuses fullscreen windows
  hl.dispatch(hl.dsp.window.pin({ action = "disable", window = window }))

  local home = origin(window)
  local was_tiled = has_tag(window, TILED_TAG)
  if was_tiled then
    hl.dispatch(hl.dsp.window.tag({ tag = "-" .. TILED_TAG, window = window }))
  end

  local key = win_key(window)
  local saved = saved_geometries[key]
  saved_geometries[key] = nil

  if home then
    hl.dispatch(hl.dsp.window.tag({ tag = "-" .. HOME_PREFIX .. home, window = window }))
    local monitor = window.monitor or hl.get_active_monitor()
    local area = monitor_work_area(monitor)
    if area then
      local x, y, w, h = clamped_centered_geometry(area, M.scratchpad_size.x, M.scratchpad_size.y)
      hl.dispatch(hl.dsp.window.resize({ x = w, y = h, window = window }))
      hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = window })) -- centerwindow only acts on the focused window
    else
      hl.dispatch(hl.dsp.window.resize({ x = M.scratchpad_size.x, y = M.scratchpad_size.y, window = window }))
    end
    hl.dispatch(hl.dsp.window.move({ workspace = "special:" .. home, follow = false, window = window }))
  elseif was_tiled and not is_special(window.workspace) then
    hl.dispatch(hl.dsp.window.float({ action = "disable", window = window }))
  elseif saved then
    hl.dispatch(hl.dsp.window.resize({ x = saved.size.x, y = saved.size.y, window = window }))
    hl.dispatch(hl.dsp.window.move({ x = saved.at.x, y = saved.at.y, window = window }))
  end
end

function M.toggle(window)
  window = window or hl.get_active_window()
  if not window then
    return
  end
  if window.pinned or window.pin_fullscreened then
    unpin(window)
  else
    pin(window)
  end
end

function M.toggle_special(name, custom_size)
  name = name or "scratchpad"
  local special_name = "special:" .. name
  local active_mon = hl.get_active_monitor()

  local was_open = active_mon
    and active_mon.active_special_workspace
    and active_mon.active_special_workspace.name == special_name

  hl.dispatch(hl.dsp.workspace.toggle_special(name)) -- single call also moves special ws open on another monitor
  if was_open then
    return
  end

  local mon = hl.get_active_monitor() or active_mon
  if not hl.get_workspace_windows then
    return
  end
  local wins = hl.get_workspace_windows(special_name) or {}
  local target_size = custom_size or M.scratchpad_size
  for _, win in ipairs(wins) do
    if not win.floating then
      hl.dispatch(hl.dsp.window.tag({ tag = "+" .. SCRATCHPAD_TILED_TAG, window = win }))
      hl.dispatch(hl.dsp.window.float({ action = "enable", window = win }))
      local area = monitor_work_area(mon)
      if area then
        local x, y, w, h = clamped_centered_geometry(area, target_size.x, target_size.y)
        hl.dispatch(hl.dsp.window.resize({ x = w, y = h, window = win }))
        hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = win }))
      end
    else
      M.clamp_to_monitor(win, mon)
    end
  end
  if wins[1] then
    hl.dispatch(hl.dsp.focus({ window = wins[1] }))
  end
end

function M.toggle_scratchpad(window, name, custom_size)
  name = name or "scratchpad"
  window = window or hl.get_active_window()
  if not window then
    return
  end

  local ws = window.workspace
  if is_special(ws) then
    local mon = window.monitor or hl.get_active_monitor()
    local target_ws = mon and mon.active_workspace or hl.get_active_workspace()
    if not target_ws or is_special(target_ws) then
      return
    end
    local restore_tiled = has_tag(window, SCRATCHPAD_TILED_TAG)
    if restore_tiled then
      hl.dispatch(hl.dsp.window.tag({ tag = "-" .. SCRATCHPAD_TILED_TAG, window = window }))
    end
    hl.dispatch(hl.dsp.window.move({ workspace = tostring(target_ws.id), window = window }))
    if restore_tiled then
      hl.dispatch(hl.dsp.window.float({ action = "disable", window = window }))
    else
      M.clamp_to_monitor(window, target_ws.monitor or mon)
    end
    return
  end

  if window.pinned or window.pin_fullscreened then
    unpin(window)
  end
  hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 0, window = window }))

  if not window.floating then
    hl.dispatch(hl.dsp.window.tag({ tag = "+" .. SCRATCHPAD_TILED_TAG, window = window }))
    hl.dispatch(hl.dsp.window.float({ action = "enable", window = window }))
  end

  local mon = window.monitor or hl.get_active_monitor()
  local area = monitor_work_area(mon)
  local size = custom_size or M.scratchpad_size
  if area then
    local x, y, w, h = clamped_centered_geometry(area, size.x, size.y)
    hl.dispatch(hl.dsp.window.resize({ x = w, y = h, window = window }))
    hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = window }))
  else
    hl.dispatch(hl.dsp.window.resize({ x = size.x, y = size.y, window = window }))
  end

  hl.dispatch(hl.dsp.window.move({ workspace = "special:" .. name, follow = false, window = window }))
end

function M.toggle_app_scratchpad(spec)
  if not spec or not spec.name or not spec.command then
    return
  end
  local special_name = "special:" .. spec.name
  local size = {
    x = spec.width or M.scratchpad_size.x,
    y = spec.height or M.scratchpad_size.y,
  }

  local existing = (hl.get_workspace_windows and (hl.get_workspace_windows(special_name) or {})[1]) or nil
  if not existing and spec.class and hl.get_windows then
    existing = (hl.get_windows({ class = spec.class }) or {})[1]
  end

  if not existing then
    hl.exec_cmd(spec.command, {
      workspace = special_name,
      float = true,
      size = string.format("%d %d", size.x, size.y),
      center = true,
    })
    return
  end

  if existing.workspace and existing.workspace.name == special_name then
    M.toggle_special(spec.name, size)
  else
    M.toggle_scratchpad(existing, spec.name, size)
    M.toggle_special(spec.name, size)
  end
end

return M
