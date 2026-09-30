local state = require("pangu.generated")
local theme = state.theme

hl.config({
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
      natural_scroll = true,
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
})

hl.curve("easeInOutQuint", { type = "bezier", points = { { 0.83, 0.0 }, { 0.17, 1.0 } } })

for _, animation in ipairs({
  { leaf = "windows", style = "slide" },
  { leaf = "windowsOut", style = "slide" },
  { leaf = "fade" },
  { leaf = "workspaces", style = "slidevert" },
}) do
  animation.enabled = theme.animations.enabled
  animation.speed = theme.animations.speed
  animation.bezier = "easeInOutQuint"
  hl.animation(animation)
end

return true
