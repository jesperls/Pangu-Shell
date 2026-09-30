{
  shell = true;
  monitors = {
    primary = null;
    primary_workspaces = [ ];
  };
  keyboard_layout = "us";
  input = {
    accel_profile = null;
    repeat_rate = 40;
    repeat_delay = 300;
    numlock = true;
  };
  render.direct_scanout = 2;
  apps = {
    terminal = "xdg-terminal-exec";
    browser = "xdg-open https://example.org";
    file_manager = "xdg-open .";
    editor = "xdg-terminal-exec vi";
    shortcuts = [ ];
  };
  tearing = {
    enable = false;
    class_patterns = [ ];
  };
  layouts = {
    default = "dwindle";
    cycle = [
      "dwindle"
      "lua:centered"
    ];
    centered = {
      master_width = 0.5;
      height_resize_step = 0.15;
      full_height = false;
      aspect = [
        16
        9
      ];
    };
  };
  auto_fake_fullscreen = {
    enable = false;
    classes = [ ];
  };
  theme = {
    animations = {
      enabled = true;
      speed = 1.0;
    };
    translucent_opacity = 1.0;
    translucent_apps = [ ];
    font_family = "Inter";
  };
}
