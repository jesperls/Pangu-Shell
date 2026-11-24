local state = require("pangu.generated")
local theme = state.theme
local touchpad = (state.input and state.input.touchpad) or {}
local gestures = state.gestures or {}

local config = {
  general = {
    layout = state.layouts.default,
    resize_on_border = true,
    allow_tearing = state.tearing.enable,
    snap = {
      enabled = true,
    },
  },
  layout = {
    single_window_aspect_ratio = { 0, 0 }, -- The centered layout already sets its own width.
  },
  animations = {
    enabled = theme.animations.enabled,
  },
  input = {
    kb_layout = state.keyboard_layout,
    follow_mouse = 1,
    touchpad = {
      natural_scroll = touchpad.natural_scroll ~= false,
      tap_to_click = touchpad.tap_to_click ~= false,
      tap_and_drag = touchpad.tap_and_drag ~= false,
      disable_while_typing = touchpad.disable_while_typing ~= false,
      clickfinger_behavior = touchpad.clickfinger_behavior == true,
      scroll_factor = touchpad.scroll_factor or 1.0,
    },
    sensitivity = 0,
    accel_profile = state.input.accel_profile,
    repeat_rate = state.input.repeat_rate,
    repeat_delay = state.input.repeat_delay,
    numlock_by_default = state.input.numlock,
  },
  render = {
    direct_scanout = state.render.direct_scanout,
  },
  dwindle = {
    preserve_split = true,
  },
  xwayland = {
    force_zero_scaling = true,
  },
  binds = {
    scroll_event_delay = 0,
    allow_pin_fullscreen = true,
  },
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    mouse_move_enables_dpms = true,
    key_press_enables_dpms = true,
    font_family = theme.font_family,
    focus_on_activate = true,
    render_unfocused_fps = 30,
  },
}

if gestures.workspace_swipe == true then
  config.gestures = {
    workspace_swipe_distance = gestures.workspace_swipe_distance or 500,
    workspace_swipe_invert = gestures.workspace_swipe_invert ~= false,
    workspace_swipe_cancel_ratio = gestures.workspace_swipe_cancel_ratio or 0.45,
    workspace_swipe_forever = gestures.workspace_swipe_forever == true,
    workspace_swipe_create_new = gestures.workspace_swipe_create_new ~= false,
    workspace_swipe_min_speed_to_force = gestures.workspace_swipe_min_speed_to_force or 30,
  }
end

hl.config(config)

hl.curve("easeInOutQuint", { type = "bezier", points = { { 0.83, 0.0 }, { 0.17, 1.0 } } })

for _, animation in ipairs({
  { leaf = "windows", style = "slide" },
  { leaf = "windowsOut", style = "slide" },
  { leaf = "fade" },
  { leaf = "workspaces", style = theme.animations.workspace_style or "slidevert" },
}) do
  animation.enabled = theme.animations.enabled
  animation.speed = theme.animations.speed
  animation.bezier = "easeInOutQuint"
  hl.animation(animation)
end

return true
