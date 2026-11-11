local source = assert(arg[1])
local count = 0
for file in io.popen("find '" .. source:gsub("'", "'\\''") .. "' -name '*.lua'"):lines() do
  assert(loadfile(file))
  count = count + 1
end
assert(count > 0, "No Lua files found in " .. source)

local session_dir = os.tmpname()
os.remove(session_dir)
local getenv = os.getenv
local instance = "first-instance"
os.getenv = function(name)
  if name == "XDG_DATA_HOME" then
    return session_dir
  end
  if name == "HYPRLAND_INSTANCE_SIGNATURE" then
    return instance
  end
  return getenv(name)
end
local first_session = dofile(source .. "/session.lua")
first_session.table("slots")[1] = { master = 0, left = { 1 }, right = { 2 } }
first_session.table("weights")[0] = 1.25
first_session.table("layout_modes")[1] = "lua:centered"
first_session.save()
local reloaded_session = dofile(source .. "/session.lua")
assert(reloaded_session.table("slots")[1].master == 0, "Reload lost live window slots")
assert(reloaded_session.table("weights")[0] == 1.25, "Reload lost live window weights")
instance = "second-instance"
local new_session = dofile(source .. "/session.lua")
assert(next(new_session.table("slots")) == nil, "A new compositor inherited slots for reused window IDs")
assert(next(new_session.table("weights")) == nil, "A new compositor inherited weights for reused window IDs")
assert(new_session.table("layout_modes")[1] == "lua:centered", "A new compositor lost workspace layout choices")
new_session.save()
assert(dofile(source .. "/session.lua").data.instance == instance, "The compositor instance was not persisted")
os.getenv = getenv
os.remove(session_dir .. "/pangu/hypr-layout-state.lua")
os.remove(session_dir .. "/pangu")
os.remove(session_dir)

local state = {
  apps = {},
  layouts = { centered = { master_width = 0.5, full_height = true, aspect = { 16, 9 }, height_resize_step = 0.15 } },
}
local slots = { [1] = { master = 10, left = { 11 }, right = { 12 } } }
local weights = { [10] = 2, [11] = 3, [12] = 4, [20] = 2 }
local custom_events = {}
local layout
package.preload["pangu.generated"] = function()
  return state
end
package.preload["pangu.gamemode"] = function()
  return {
    on_change = function() end,
    is_active = function()
      return false
    end,
  }
end
package.preload["pangu.session"] = function()
  return {
    table = function(key)
      return key == "slots" and slots or weights
    end,
    save = function() end,
  }
end
hl = {
  on = function() end,
  dsp = {
    event = function(payload)
      return payload
    end,
  },
  dispatch = function(payload)
    custom_events[#custom_events + 1] = payload
  end,
  get_monitors = function()
    return {
      {
        name = "DP-2",
        x = 0,
        y = 0,
        width = 5120,
        height = 1440,
        scale = 1,
        transform = 0,
        active_workspace = {
          id = 1,
          tiled_layout = "lua:centered",
        },
      },
    }
  end,
  get_workspace_windows = function(id)
    return id == 1 and { { stable_id = 10, floating = false, fullscreen = 0 } } or {}
  end,
  get_windows = function()
    return {
      { stable_id = 10, floating = false, fullscreen = 0, workspace = { id = 1 } },
      { stable_id = 11, floating = false, fullscreen = 0, workspace = { id = 1 } },
      { stable_id = 12, floating = false, fullscreen = 0, workspace = { id = 1 } },
      { stable_id = 20, floating = false, fullscreen = 0, workspace = { id = 2 } },
    }
  end,
  get_workspaces = function()
    return { { id = 1 }, { id = 2 }, { name = "special:scratchpad", id = nil, special = true } }
  end,
  timer = function()
    return { set_enabled = function() end }
  end,
  layout = {
    register = function(_, implementation)
      layout = implementation
    end,
  },
}
local layouts_mod = dofile(source .. "/layouts.lua")
layouts_mod.emit_gaps(false)
assert(#custom_events == 1 and custom_events[1] == "centergap,DP-2,1280,2560,0", "Initial centergap was not emitted")
layouts_mod.emit_gaps(false)
assert(#custom_events == 1, "Unforced emit_gaps re-emitted unchanged centergap")
layouts_mod.emit_gaps(true)
assert(#custom_events == 2 and custom_events[2] == "centergap,DP-2,1280,2560,0", "Forced emit_gaps must re-emit centergap for restarted shell")
layout.layout_msg({ targets = { { window = { workspace = { id = 1 } } } } }, "equalize")
assert(weights[10] == nil and weights[11] == nil and weights[12] == nil)
assert(weights[20] == 2, "Equalize changed another workspace")

local appliedSettings
hl.config = function(config)
  appliedSettings = config
end
state.theme = { animations = { enabled = true } }
state.tearing = { enable = false }
state.input, state.render = {}, {}
hl.curve, hl.animation = function() end, function() end
dofile(source .. "/settings.lua")
assert(
  appliedSettings.layout.single_window_aspect_ratio[2] == 0,
  "Global single-window padding must not shrink an already centered layout"
)
local placed
local target = {
  window = { stable_id = 99, active = true, workspace = { id = 99 } },
  place = function(_, box)
    placed = box
  end,
}
layout.recalculate({ area = { x = 0, y = 44, w = 5120, h = 1396 }, targets = { target } })
assert(placed.w == 2560 and placed.x == 1280, "Single centered window lost its width")

local binds, bind_flags, dispatched, drag_started, release_binds = {}, {}, 0, 0, 0
local floating = true
local function dispatcher()
  return {}
end
hl = {
  bind = function(_, callback, flags)
    if flags.description then
      binds[flags.description] = callback
      bind_flags[flags.description] = flags
    elseif flags.release then
      release_binds = release_binds + 1
    end
  end,
  dsp = setmetatable({
    window = setmetatable({}, {
      __index = function()
        return dispatcher
      end,
    }),
    workspace = setmetatable({}, {
      __index = function()
        return dispatcher
      end,
    }),
  }, {
    __index = function()
      return dispatcher
    end,
  }),
  dispatch = function()
    dispatched = dispatched + 1
  end,
  get_active_workspace = function()
    return { tiled_layout = "lua:centered" }
  end,
  get_active_window = function()
    return { floating = floating }
  end,
}
package.preload["pangu.layouts"] = function()
  return {
    start_drag = function()
      drag_started = drag_started + 1
    end,
    end_drag = function() end,
  }
end
package.preload["pangu.layout_modes"] = function()
  return { toggle = function() end }
end
package.preload["pangu.fullscreen"] = function()
  return {}
end
package.preload["pangu.popout"] = function()
  return {}
end
dofile(source .. "/binds.lua")
for _, desc in ipairs({
  "Mouse: drag window",
  "Mouse: resize window",
  "Mouse: drag window (side button)",
  "Mouse: resize window (side button)",
}) do
  local f = assert(bind_flags[desc], "Missing mouse bind: " .. desc)
  assert(not f.drag and not f.release, desc .. " must fire on button-down, not drag/release")
end
assert(release_binds == 2, "Mouse release cleanup binds must omit description so cheatsheet hides them")
binds["Mouse: resize window"]()
binds["Mouse: resize window (side button)"]()
assert(dispatched == 2 and drag_started == 0, "Floating windows cannot be resized in centered workspaces")
floating = false
binds["Mouse: resize window"]()
assert(dispatched == 2 and drag_started == 1, "Tiled centered window used the floating resize dispatcher")

local modes = { [1] = "lua:centered", [2] = "dwindle", [3] = "bogus", [4] = "lua:centered" }
local ruled = {}
local handlers = {}
local live = {
  [1] = { id = 1, monitor = { name = "primary" }, tiled_layout = "lua:centered" },
  [4] = { id = 4, monitor = { name = "secondary" }, tiled_layout = "dwindle" },
}
for _, name in ipairs({ "pangu.generated", "pangu.session", "pangu.layouts", "pangu.primary" }) do
  package.loaded[name] = nil
end
package.preload["pangu.generated"] = function()
  return { layouts = { default = "dwindle", cycle = { "dwindle", "lua:centered" } }, monitors = {} }
end
package.preload["pangu.session"] = function()
  return {
    table = function()
      return modes
    end,
    save = function() end,
  }
end
package.preload["pangu.layouts"] = function()
  return { center_active = function() end, schedule_scan = function() end }
end
hl = {
  get_workspace = function(id)
    return live[id]
  end,
  on = function(event, callback)
    handlers[event] = callback
  end,
  workspace_rule = function(rule)
    rule.enabled = true
    ruled[#ruled + 1] = rule
    return {
      set_enabled = function(_, enabled)
        rule.enabled = enabled
      end,
    }
  end,
}
package.preload["pangu.primary"] = function()
  return {
    workspace_id = function(id)
      return id == 4
    end,
    workspace = function(workspace)
      return workspace.monitor.name == "primary"
    end,
  }
end
dofile(source .. "/layout_modes.lua")
assert(modes[1] == "lua:centered", "A live-primary centered mode was deleted on restore")
assert(modes[2] == "dwindle")
assert(modes[3] == nil, "An invalid layout mode target was not discarded")
assert(#ruled == 2, "Restore must use the live monitor before the static mapping")
live[4].monitor.name = "primary"
handlers["workspace.move_to_monitor"](live[4])
assert(#ruled == 3 and ruled[3].layout == "lua:centered", "A preserved mode was not restored on the primary monitor")
live[4].tiled_layout = "lua:centered"
live[4].monitor.name = "secondary"
handlers["workspace.move_to_monitor"](live[4])
assert(ruled[3].enabled == false, "Centered layout stayed enabled on the secondary monitor")
assert(#ruled == 4 and ruled[4].layout == "dwindle" and ruled[4].enabled == false, "Secondary monitor did not fall back to default layout")
live[4].tiled_layout = "dwindle"
live[4].monitor.name = "primary"
handlers["workspace.move_to_monitor"](live[4])
assert(#ruled == 5 and ruled[5].layout == "lua:centered" and ruled[5].enabled == true, "Fresh rule was not recreated on return")
print("Hyprland syntax, workspace isolation, floating resize and layout-mode restore tests passed")
