local state = require("pangu.generated")
local popout = require("pangu.popout")

for _, class in ipairs({
  "pavucontrol",
  "blueman-manager",
  "nm-connection-editor",
  "org.gnome.Calculator",
  "org.gnome.NautilusPreviewer",
  "eog",
  "vlc",
  "imv",
  "feh",
  "file-roller",
  "qpwgraph",
  "org.pulseaudio.pavucontrol",
  "overskride",
  "scrcpy",
  "xdg-desktop-portal-gtk",
  "hyprpolkitagent",
}) do
  hl.window_rule({ match = { class = class }, float = true })
end

for _, title in ipairs({
  "^(Open File)$",
  "^(Save File)$",
  "^(Confirm to replace files)$",
  "^(File Operation Progress)$",
}) do
  hl.window_rule({ match = { title = title }, float = true })
end

require("pangu.shell_rules")

hl.window_rule({
  match = { title = "^(Picture-in-Picture)$" },
  float = true,
  pin = true,
  size = { 640, 360 },
  move = { "monitor_w - 660", "monitor_h - 380" },
})

hl.window_rule({
  match = { workspace = "special:scratchpad" },
  float = true,
  center = true,
  size = { popout.scratchpad_size.x, popout.scratchpad_size.y },
})

local translucent = string.format("%.2f %.2f", state.theme.translucent_opacity, state.theme.translucent_opacity)
for _, class in ipairs(state.theme.translucent_apps) do
  hl.window_rule({ match = { class = class }, opacity = translucent })
end

if state.tearing.enable then
  for _, pattern in ipairs(state.tearing.class_patterns) do
    hl.window_rule({ match = { class = pattern }, immediate = true })
  end
end

hl.window_rule({ match = { title = "Sharing your screen" }, opacity = "1.0 override 1.0 override" })
hl.window_rule({ match = { title = "sharing indicator" }, opacity = "1.0 override 1.0 override" })

return true
