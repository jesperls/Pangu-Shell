local source = assert(arg[1])

local function reset_modules()
  for _, name in ipairs({
    "pangu.generated",
    "pangu.popout",
    "pangu.events",
    "pangu.fullscreen",
    "pangu.primary",
  }) do
    package.loaded[name] = nil
    package.preload[name] = nil
  end
end

-- 1. Popout & Scratchpad behavior tests
reset_modules()
package.preload["pangu.generated"] = function()
  return { scratchpad = { width = 900, height = 700 } }
end

local dispatches = {}
local execs = {}
local close_cb
local dp2 = {
  name = "DP-2",
  x = 0,
  y = 0,
  width = 5120,
  height = 1440,
  scale = 1,
  transform = 0,
  active_workspace = { id = 1, name = "1" },
  active_special_workspace = nil,
}
dp2.active_workspace.monitor = dp2
local dp3 = {
  name = "DP-3",
  x = 5120,
  y = 0,
  width = 2560,
  height = 1440,
  scale = 1,
  transform = 0,
  active_workspace = { id = 2, name = "2" },
  active_special_workspace = nil,
}
dp3.active_workspace.monitor = dp3

local active_mon = dp2
local active_win = nil
local special_windows = {}
local all_windows = {}

local function apply_tag(win, expr)
  win.tags = win.tags or {}
  local op, tag = expr:match("^([+-])(.+)$")
  if op == "+" then
    win.tags[#win.tags + 1] = tag
  elseif op == "-" then
    for i = #win.tags, 1, -1 do
      if win.tags[i] == tag then
        table.remove(win.tags, i)
      end
    end
  end
end

hl = {
  on = function(ev, cb)
    if ev == "window.close" then
      close_cb = cb
    end
  end,
  exec_cmd = function(cmd, rules)
    execs[#execs + 1] = { cmd = cmd, rules = rules }
  end,
  get_active_monitor = function()
    return active_mon
  end,
  get_active_workspace = function()
    return active_mon.active_workspace
  end,
  get_active_window = function()
    return active_win
  end,
  get_monitors = function()
    return { dp2, dp3 }
  end,
  get_workspace_windows = function(name)
    return special_windows[name] or {}
  end,
  get_windows = function(filter)
    if not filter or not filter.class then
      return all_windows
    end
    local out = {}
    for _, w in ipairs(all_windows) do
      if w.class == filter.class then
        out[#out + 1] = w
      end
    end
    return out
  end,
  dispatch = function(d)
    dispatches[#dispatches + 1] = d
    if d.kind == "tag" then
      apply_tag(d.args.window, d.args.tag)
    elseif d.kind == "float" then
      d.args.window.floating = (d.args.action == "enable")
    elseif d.kind == "pin" then
      d.args.window.pinned = (d.args.action == "enable")
    elseif d.kind == "resize" then
      d.args.window.size = { x = d.args.x, y = d.args.y }
    elseif d.kind == "move" and d.args.workspace then
      local ws_name = tostring(d.args.workspace)
      if ws_name:sub(1, 8) == "special:" then
        d.args.window.workspace = { id = -99, name = ws_name, monitor = active_mon }
        special_windows[ws_name] = special_windows[ws_name] or {}
        table.insert(special_windows[ws_name], d.args.window)
      else
        d.args.window.workspace = { id = tonumber(ws_name) or 1, name = ws_name, monitor = active_mon }
      end
    elseif d.kind == "move" and d.args.x then
      d.args.window.at = { x = d.args.x, y = d.args.y }
    elseif d.kind == "toggle_special" then
      local sname = "special:" .. d.args
      for _, m in ipairs({ dp2, dp3 }) do
        if m.active_special_workspace and m.active_special_workspace.name == sname then
          m.active_special_workspace = nil
          return
        end
      end
      active_mon.active_special_workspace = { id = -99, name = sname }
    end
  end,
  dsp = {
    focus = function(args)
      return { kind = "focus", args = args }
    end,
    window = {
      tag = function(args)
        return { kind = "tag", args = args }
      end,
      float = function(args)
        return { kind = "float", args = args }
      end,
      pin = function(args)
        return { kind = "pin", args = args }
      end,
      resize = function(args)
        return { kind = "resize", args = args }
      end,
      move = function(args)
        return { kind = "move", args = args }
      end,
      fullscreen_state = function(args)
        return { kind = "fullscreen_state", args = args }
      end,
      set_prop = function(args)
        return { kind = "set_prop", args = args }
      end,
    },
    workspace = {
      toggle_special = function(name)
        return { kind = "toggle_special", args = name }
      end,
    },
  },
}

local popout = dofile(source .. "/popout.lua")

-- Pin drops fullscreen BEFORE float/pin and restores floating geometry on unpin
local float_win = {
  stable_id = "w1",
  floating = true,
  pinned = false,
  at = { x = 300, y = 250 },
  size = { x = 800, y = 600 },
  workspace = dp2.active_workspace,
  monitor = dp2,
}
popout.toggle(float_win)
assert(dispatches[1].kind == "fullscreen_state", "pin must drop fullscreen before floating/pinning")
assert(float_win.pinned and float_win.size.x == 640 and float_win.at.x == 5120 - 640 - 20)
popout.toggle(float_win)
assert(not float_win.pinned and float_win.size.x == 800 and float_win.at.x == 300, "unpin must restore saved floating geometry")

-- Bidirectional stash / un-stash preserves tiled state
local tiled_win = {
  stable_id = "w2",
  floating = false,
  pinned = false,
  workspace = dp2.active_workspace,
  monitor = dp2,
}
active_win = tiled_win
popout.toggle_scratchpad()
assert(tiled_win.floating and tiled_win.workspace.name == "special:scratchpad", "stash must float and move to special:scratchpad")
assert(tiled_win.size.x == 900 and tiled_win.size.y == 700, "stash must resize to scratchpad_size")

-- Leave scratchpad open on DP-3 with off-screenDP-2 coordinates, then toggle_special on DP-2: moves in 1 press & clamps
tiled_win.at = { x = 6000, y = 200 }
dp3.active_special_workspace = { id = -99, name = "special:scratchpad" }
active_mon = dp2
popout.toggle_special("scratchpad")
assert(dp3.active_special_workspace == nil and dp2.active_special_workspace ~= nil, "toggle_special must pull open scratchpad across monitors in one press")
assert(tiled_win.at.x >= 0 and tiled_win.at.x + tiled_win.size.x <= 5120, "toggle_special must clamp window onto target monitor")

-- Un-stash restores tiled window to regular workspace and disables float
popout.toggle_scratchpad(tiled_win)
assert(tiled_win.workspace.id == 1 and not tiled_win.floating, "unstash must restore tiled state on regular workspace")
close_cb(float_win)

-- Named app scratchpad launches on first use
popout.toggle_app_scratchpad({ name = "term", command = "kitty --class scratch-term", class = "scratch-term", width = 1000, height = 650 })
assert(
  #execs == 1
    and execs[1].cmd == "kitty --class scratch-term"
    and type(execs[1].rules) == "table"
    and execs[1].rules.workspace == "special:term"
    and execs[1].rules.float == true
    and execs[1].rules.size == "1000 650"
    and execs[1].rules.center == true,
  "app scratchpad must launch via hl.exec_cmd rules table"
)

-- 2. Events: secondary-monitor pinned PiP & unconditional sync_fullscreen restore
reset_modules()
package.preload["pangu.generated"] = function()
  return { auto_fake_fullscreen = { enable = true, classes = { "firefox" } }, monitors = { primary = "DP-2" } }
end
package.preload["pangu.fullscreen"] = function()
  return { suppress = false }
end
package.preload["pangu.popout"] = function()
  return {
    toggle = function(w)
      w.popout_toggled = true
    end,
  }
end
package.preload["pangu.primary"] = function()
  return dofile(source .. "/primary.lua")
end

local event_handlers = {}
dispatches = {}
hl.on = function(ev, cb)
  event_handlers[ev] = cb
end
dofile(source .. "/events.lua")

-- Unpinned browser window in multi-tiled workspace gets sync_fullscreen restored
local browser_win = {
  class = "firefox",
  fullscreen = 2,
  fullscreen_client = 2,
  pinned = false,
  monitor = dp2,
  workspace = {
    get_windows = function()
      return { { floating = false }, { floating = false } }
    end,
  },
}
event_handlers["window.fullscreen"](browser_win)
assert(#dispatches == 2 and dispatches[2].kind == "set_prop" and dispatches[2].args.prop == "sync_fullscreen", "unpinned demotion must restore sync_fullscreen")

-- Pinned PiP window on secondary monitor DP-3 still gets demoted instead of blowing up fullscreen
dispatches = {}
local pip_secondary = {
  class = "firefox",
  fullscreen = 2,
  fullscreen_client = 2,
  pinned = false,
  pin_fullscreened = true,
  monitor = dp3,
}
event_handlers["window.fullscreen"](pip_secondary)
assert(#dispatches == 3 and dispatches[1].kind == "fullscreen_state" and dispatches[3].kind == "pin", "secondary monitor pinned window must stay demoted and pinned")

-- Async Wayland PiP title change auto-triggers popout
local async_pip = { title = "Picture in picture", pinned = false }
event_handlers["window.title"](async_pip)
assert(async_pip.popout_toggled, "async Picture-in-Picture title must trigger popout")

-- 3. Primary monitor desc: prefix & DPMS cache
reset_modules()
package.preload["pangu.generated"] = function()
  return { monitors = { primary = "desc:Samsung Odyssey", primary_workspaces = { 1 } } }
end
local primary_desc = dofile(source .. "/primary.lua")
assert(primary_desc.monitor({ name = "DP-2", description = "Samsung Odyssey G9 (DP-2)" }), "desc: must match description prefix")

reset_modules()
package.preload["pangu.generated"] = function()
  return { monitors = { primary = nil, primary_workspaces = {} } }
end
local monitors_list = { { name = "DP-2" }, { name = "DP-3" } }
hl.get_monitors = function()
  return monitors_list
end
local primary_cached = dofile(source .. "/primary.lua")
assert(primary_cached.monitor({ name = "DP-2" }))
monitors_list = { { name = "DP-3" }, { name = "DP-2" } }
assert(primary_cached.monitor({ name = "DP-2" }) and not primary_cached.monitor({ name = "DP-3" }), "primary monitor must stay cached across DPMS reorder")

print("Hyprland popout, scratchpad, fullscreen, PiP and primary-monitor behavior tests passed")
