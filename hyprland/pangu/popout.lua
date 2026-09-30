local SIZE = { x = 640, y = 360 }
local MARGIN = 20
local TILED_TAG = "popout_was_tiled"
local HOME_PREFIX = "popout_from_"

local M = {
  scratchpad_size = { x = 900, y = 700 },
}

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

local function pin(window)
  local workspace = window.workspace
  local monitor = workspace and workspace.monitor

  if workspace and workspace.id < 0 then
    local home = workspace.name:match("^special:(.+)$")
    if home then
      hl.dispatch(hl.dsp.window.tag({ tag = "+" .. HOME_PREFIX .. home, window = window }))
    end
  end

  if not window.floating then
    hl.dispatch(hl.dsp.window.tag({ tag = "+" .. TILED_TAG, window = window }))
    hl.dispatch(hl.dsp.window.float({ action = "enable", window = window }))
  end

  hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 0, window = window }))
  hl.dispatch(hl.dsp.window.pin({ action = "enable", window = window }))
  hl.dispatch(hl.dsp.window.resize({ x = SIZE.x, y = SIZE.y, window = window }))

  if monitor then
    local width, height = monitor.width, monitor.height
    if (monitor.transform or 0) % 2 == 1 then
      width, height = height, width
    end
    local scale = monitor.scale or 1
    hl.dispatch(hl.dsp.window.move({
      x = monitor.x + math.floor(width / scale) - SIZE.x - MARGIN,
      y = monitor.y + math.floor(height / scale) - SIZE.y - MARGIN,
      window = window,
    }))
  end
end

local function unpin(window)
  -- pinning refuses fullscreen windows, so drop any fullscreen first
  hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 0, window = window }))
  hl.dispatch(hl.dsp.window.pin({ action = "disable", window = window }))

  local home = origin(window)
  if home then
    hl.dispatch(hl.dsp.window.tag({ tag = "-" .. HOME_PREFIX .. home, window = window }))
    hl.dispatch(hl.dsp.window.move({ workspace = "special:" .. home, follow = false, window = window }))
  end

  if has_tag(window, TILED_TAG) then
    hl.dispatch(hl.dsp.window.tag({ tag = "-" .. TILED_TAG, window = window }))
    if not window.workspace or window.workspace.id > 0 then
      hl.dispatch(hl.dsp.window.float({ action = "disable", window = window }))
    end
  elseif home == "scratchpad" then
    hl.dispatch(hl.dsp.window.resize({ x = M.scratchpad_size.x, y = M.scratchpad_size.y, window = window }))
    hl.dispatch(hl.dsp.window.center({ window = window }))
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

return M
