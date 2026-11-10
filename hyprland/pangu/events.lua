local state = require("pangu.generated")
local fullscreen = require("pangu.fullscreen")
local popout = require("pangu.popout")
local primary = require("pangu.primary")

local classes = {}
for _, class in ipairs(state.auto_fake_fullscreen.classes) do
  classes[class] = true
end

local demoting = false

hl.on("window.fullscreen", function(window)
  if
    demoting
    or fullscreen.suppress
    or not window
    or (window.fullscreen ~= 2 and window.fullscreen_client ~= 2)
  then
    return
  end

  local pinned = window.pinned or window.pin_fullscreened

  if not pinned then
    if not primary.monitor(window.monitor) then
      return
    end
    if not state.auto_fake_fullscreen.enable or not classes[window.class] then
      return
    end

    local workspace = window.workspace
    if not workspace then
      return
    end

    local tiled = 0
    for _, other in ipairs(workspace:get_windows()) do
      if not other.floating then
        tiled = tiled + 1
      end
    end
    if tiled < 2 then
      return
    end
  end

  demoting = true
  pcall(hl.dispatch, hl.dsp.window.fullscreen_state({
    internal = 0,
    client = 2,
    window = window,
  }))
  demoting = false

  pcall(hl.dispatch, hl.dsp.window.set_prop({
    prop = "sync_fullscreen", -- fullscreen_state clears sync_fullscreen; restore so client exit works
    value = "1",
    window = window,
  }))

  if pinned and not window.pinned then
    pcall(hl.dispatch, hl.dsp.window.pin({ action = "enable", window = window }))
  end
end)

hl.on("window.title", function(window)
  if not window or window.pinned or window.pin_fullscreened then
    return
  end
  local title = tostring(window.title or "")
  if title == "Picture-in-Picture" or title == "Picture in Picture" or title == "Picture in picture" then
    popout.toggle(window)
  end
end)

return true
