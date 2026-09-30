-- Contract between the Nix generated.lua writer and the Lua readers. The
-- behavior test stubs the state, so without this a renamed or re-nested Nix
-- key only fails at runtime in the compositor.
local generated = assert(arg[1], "usage: hyprland_contract.lua <generated.lua>")

local chunk = assert(loadfile(generated))
package.preload["pangu.generated"] = chunk
local state = require("pangu.generated")

local function get(path)
  local current = state
  for part in path:gmatch("[^.]+") do
    if type(current) ~= "table" then
      return nil
    end
    current = current[part]
  end
  return current
end

-- Every state path the share/hypr modules read.
local required = {
  "shell",
  "apps.terminal", "apps.browser", "apps.file_manager", "apps.editor",
  "layouts.default", "layouts.cycle",
  "layouts.centered.master_width", "layouts.centered.full_height",
  "layouts.centered.height_resize_step", "layouts.centered.aspect",
  "auto_fake_fullscreen.enable", "auto_fake_fullscreen.classes",
  "monitors.primary_workspaces",
  "theme.animations.enabled", "theme.animations.speed",
  "theme.translucent_opacity", "theme.translucent_apps", "theme.font_family",
  "keyboard_layout",
  "input.repeat_rate", "input.repeat_delay", "input.numlock",
  "render.direct_scanout",
  "tearing.enable", "tearing.class_patterns",
}

for _, path in ipairs(required) do
  assert(get(path) ~= nil, "generated.lua is missing " .. path)
end

assert(type(get("layouts.cycle")) == "table", "layouts.cycle must be a list")
assert(type(get("auto_fake_fullscreen.classes")) == "table", "auto_fake_fullscreen.classes must be a list")
assert(
  type(get("layouts.centered.aspect")) == "table" and #get("layouts.centered.aspect") == 2,
  "layouts.centered.aspect must be a {width, height} pair"
)

print("generated.lua matches the Lua reader contract")
