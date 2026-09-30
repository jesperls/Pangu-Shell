local state = require("pangu.generated")

local apps = state.apps
local mainMod = "SUPER"

local function combo(mods, key)
  if mods == "" then
    return key
  end
  return (mods:gsub("%s+", " + ")) .. " + " .. key
end

local function bind(mods, key, dispatcher, desc, flags)
  flags = flags or {}
  flags.description = desc
  hl.bind(combo(mods, key), dispatcher, flags)
end

local function bind_exec(mods, key, command, desc, flags)
  bind(mods, key, hl.dsp.exec_cmd(command), desc, flags)
end

local function in_centered()
  local workspace = hl.get_active_workspace()
  return workspace ~= nil and workspace.tiled_layout == "lua:centered"
end

bind_exec(mainMod, "T", apps.terminal, "Apps: terminal")
bind_exec(mainMod, "B", apps.browser, "Apps: browser")
bind_exec(mainMod, "E", apps.file_manager, "Apps: file manager")
bind_exec(mainMod, "C", apps.editor, "Apps: editor")
for _, shortcut in ipairs(apps.shortcuts or {}) do
  bind_exec(shortcut.mods or mainMod, shortcut.key, shortcut.command, shortcut.description)
end
bind(mainMod .. " SHIFT", "W", function()
  local win = hl.get_windows({ class = "Linux Wallpaper Engine" })[1]
  if win then
    hl.dispatch(hl.dsp.focus({ window = win }))
  else
    hl.exec_cmd("linux-wallpaperengine")
  end
end, "Apps: wallpaper engine (focus or launch)")
bind_exec(mainMod, "Super_L", "pangu run launcher", "Shell: launcher", { release = true })

bind_exec(mainMod, "A", "pangu run dashboard", "Shell: dashboard")
bind_exec(mainMod, "N", "pangu run notes", "Shell: notes")
bind_exec(mainMod, "Tab", "pangu run overview", "Shell: workspace overview")
bind_exec(mainMod, "Escape", "pangu run powermenu", "Shell: power menu")
bind_exec(mainMod, "G", "pangu run gamemode", "Shell: toggle game mode")
bind_exec(mainMod, "X", "pangu run tools", "Shell: tools menu")
bind_exec(mainMod, "I", "pangu run settings", "Shell: settings")
bind_exec(mainMod, "F1", "pangu run cheatsheet", "Shell: keybind cheatsheet")
bind_exec(mainMod .. " SHIFT", "M", "pangu run macros", "Shell: macros and hotkeys")

bind_exec(mainMod, "L", "pangu lock", "Session: lock")

bind(mainMod, "Q", hl.dsp.window.close(), "Window: close")
bind(mainMod, "W", hl.dsp.window.float({ action = "toggle" }), "Window: toggle floating")
local fullscreen = require("pangu.fullscreen")
local real_fullscreen = hl.dsp.window.fullscreen({ mode = "fullscreen" })
local real_maximize = hl.dsp.window.fullscreen({ mode = "maximized" })
bind(mainMod, "F", function()
  fullscreen.dispatch_real(real_fullscreen) -- Suppress automatic demotion for explicit fullscreen.
end, "Window: fullscreen")
bind(mainMod .. " SHIFT", "F", function()
  fullscreen.dispatch_real(real_maximize)
end, "Window: maximize")
bind(
  mainMod .. " CTRL",
  "F",
  hl.dsp.window.fullscreen_state({ internal = 0, client = 2, action = "toggle" }),
  "Window: fake fullscreen"
)
bind(mainMod, "J", hl.dsp.layout("togglesplit"), "Window: toggle split direction")
bind("ALT", "Tab", hl.dsp.focus({ last = true }), "Window: focus last")

for key, direction in pairs({ left = "l", right = "r", up = "u", down = "d" }) do
  bind(mainMod, key, hl.dsp.focus({ direction = direction }), "Focus: " .. key)

  local move = hl.dsp.window.move({ direction = direction })
  bind(mainMod .. " SHIFT", key, function()
    if in_centered() then
      hl.dispatch(hl.dsp.layout("move " .. direction))
    else
      hl.dispatch(move)
    end
  end, "Window: move " .. key)
end

local function sign_step(value, step)
  return (value > 0 and "+" or "-") .. step
end

for key, delta in pairs({ up = -30, down = 30, k = -30, j = 30 }) do
  bind(mainMod .. " CTRL", key, function()
    local window = hl.get_active_window()
    if in_centered() and window and not window.floating then
      hl.dispatch(hl.dsp.layout("vresize " .. sign_step(delta, state.layouts.centered.height_resize_step)))
    end
  end, "Centered: grow/shrink side window (" .. key .. ")", { repeating = true })
end

local layouts = require("pangu.layouts")

bind(mainMod, "mouse:272", hl.dsp.window.drag(), "Mouse: drag window")
bind(mainMod, "mouse:273", function()
  local window = hl.get_active_window()
  if not in_centered() or (window and window.floating) then
    hl.dispatch(hl.dsp.window.resize())
  end
end, "Mouse: resize window")
bind(mainMod, "mouse:273", layouts.start_drag, "Centered: start weight drag")
bind(mainMod, "mouse:273", layouts.end_drag, "Centered: end weight drag", { release = true })

bind("", "mouse:275", hl.dsp.window.drag(), "Mouse: drag window (side button)")
bind("", "mouse:276", function()
  local window = hl.get_active_window()
  if not in_centered() or (window and window.floating) then
    hl.dispatch(hl.dsp.window.resize())
  end
end, "Mouse: resize window (side button)")
bind("", "mouse:276", layouts.start_drag, "Centered: start weight drag")
bind("", "mouse:276", layouts.end_drag, "Centered: end weight drag", { release = true })
bind("", "mouse:277", hl.dsp.window.close(), "Mouse: close window (side button)")

local layout_modes = require("pangu.layout_modes")

bind(mainMod, "O", layout_modes.toggle, "Layout: cycle workspace layout")

local function centered_only(msg)
  return function()
    if in_centered() then
      hl.dispatch(hl.dsp.layout(msg))
    end
  end
end

bind(mainMod, "Return", centered_only("promote"), "Centered: promote to master")
bind(mainMod, "mouse:274", function()
  if not in_centered() then
    layout_modes.set("lua:centered")
  elseif layouts.master_focused() then
    layout_modes.toggle()
  else
    hl.dispatch(hl.dsp.layout("promote"))
  end
end, "Centered: toggle layout / promote")
bind(mainMod .. " CTRL", "Return", centered_only("equalize"), "Centered: equalize weights")

for workspace = 1, 10 do
  local key = tostring(workspace % 10)
  local workspace_id = tostring(workspace)

  bind(mainMod, key, hl.dsp.focus({ workspace = workspace_id }), "Workspace: focus " .. workspace_id)
  bind(
    mainMod .. " SHIFT",
    key,
    hl.dsp.window.move({ workspace = workspace_id }),
    "Workspace: move window to " .. workspace_id
  )
end

bind(mainMod, "mouse_up", hl.dsp.focus({ workspace = "r-1" }), "Workspace: previous (scroll)")
bind(mainMod, "mouse_down", hl.dsp.focus({ workspace = "r+1" }), "Workspace: next (scroll)")
bind(mainMod, "period", hl.dsp.focus({ workspace = "r+1" }), "Workspace: next")
bind(mainMod, "comma", hl.dsp.focus({ workspace = "r-1" }), "Workspace: previous")
bind(mainMod .. " SHIFT", "mouse_up", hl.dsp.window.move({ workspace = "r-1" }), "Workspace: move window back (scroll)")
bind(mainMod .. " SHIFT", "mouse_down", hl.dsp.window.move({ workspace = "r+1" }), "Workspace: move window forward (scroll)")

bind(mainMod, "S", hl.dsp.workspace.toggle_special("scratchpad"), "Special: toggle scratchpad")
bind(
  mainMod .. " SHIFT",
  "S",
  hl.dsp.window.move({ workspace = "special:scratchpad" }),
  "Special: move window to scratchpad"
)
local popout = require("pangu.popout")
bind(mainMod, "P", function()
  popout.toggle()
end, "Special: toggle popout pin (sticky on all workspaces)")

bind(mainMod .. " CTRL", "period", hl.dsp.focus({ monitor = "-1" }), "Monitor: focus previous")
bind(mainMod .. " CTRL", "comma", hl.dsp.focus({ monitor = "+1" }), "Monitor: focus next")
bind(mainMod .. " SHIFT", "period", hl.dsp.window.move({ monitor = "-1" }), "Monitor: move window to previous")
bind(mainMod .. " SHIFT", "comma", hl.dsp.window.move({ monitor = "+1" }), "Monitor: move window to next")

bind_exec(mainMod, "V", "pangu run clipboard", "Shell: clipboard history")
bind_exec(mainMod .. " SHIFT", "C", "hyprpicker -a", "Tools: color picker")

bind_exec("", "Print", "pangu run screenshot", "Tools: screenshot")
bind_exec(
  mainMod .. " SHIFT",
  "Print",
  "grim - | wl-copy && notify-send 'Screenshot Taken' 'Full screen copied to clipboard' -i video-display",
  "Tools: full-screen screenshot to clipboard"
)

for key, spec in pairs({
  XF86AudioRaiseVolume = { "pamixer -i 5", "Media: volume up" },
  XF86AudioLowerVolume = { "pamixer -d 5", "Media: volume down" },
  XF86AudioMute = { "pamixer -t", "Media: mute" },
  XF86AudioMicMute = { "pamixer --default-source -t", "Media: mic mute" },
}) do
  bind_exec("", key, spec[1], spec[2], { repeating = true })
end

for key, spec in pairs({
  XF86AudioPlay = { "playerctl play-pause", "Media: play/pause" },
  XF86AudioPause = { "playerctl play-pause", "Media: play/pause" },
  XF86AudioNext = { "playerctl next", "Media: next" },
  XF86AudioPrev = { "playerctl previous", "Media: previous" },
  XF86AudioStop = { "playerctl stop", "Media: stop" },
}) do
  bind_exec("", key, spec[1], spec[2], { locked = true })
end

bind_exec("", "XF86MonBrightnessUp", "brightnessctl set 5%+", "Media: brightness up", { repeating = true })
bind_exec("", "XF86MonBrightnessDown", "brightnessctl set 5%-", "Media: brightness down", { repeating = true })

local dataHome = os.getenv("XDG_DATA_HOME") or ((os.getenv("HOME") or "/nonexistent") .. "/.local/share")
local macroChunk = loadfile(dataHome .. "/pangu/macros.lua")
if macroChunk then
  local ok, err = pcall(macroChunk)
  if not ok then
    io.stderr:write("pangu: failed to apply macros.lua: " .. tostring(err) .. "\n")
  end
end

return true
