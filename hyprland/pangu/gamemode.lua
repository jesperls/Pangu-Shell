local data = os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")
local path = data .. "/pangu/gamemode.lua"
local interval = 200

local active = {}
local listeners = {}
local last_text

local M = {}

function M.is_active(workspace_id)
  return active[workspace_id] ~= nil
end

function M.on_change(callback)
  listeners[#listeners + 1] = callback
end

local function enable(id) -- Recreate rules because set_enabled does not re-evaluate windows.
  active[id] = {
    hl.workspace_rule({
      workspace = "r[" .. id .. "-" .. id .. "]s[0]",
      gaps_in = 0,
      gaps_out = 0,
      border_size = 0,
      no_rounding = true,
      no_shadow = true,
    }),
    hl.window_rule({
      match = { workspace = tostring(id) },
      no_anim = true,
      no_blur = true,
    }),
  }
end

local function disable(id)
  for _, rule in ipairs(active[id]) do
    rule:set_enabled(false)
  end
  active[id] = nil
end

local function apply(desired)
  local changed = false

  for id in pairs(desired) do
    if not active[id] then
      enable(id)
      changed = true
    end
  end
  for id in pairs(active) do
    if not desired[id] then
      disable(id)
      changed = true
    end
  end

  if changed then
    for _, callback in ipairs(listeners) do
      callback()
    end
  end
end

local function poll()
  local file = io.open(path, "r")
  if not file then
    if last_text ~= nil then
      last_text = nil
      apply({})
    end
    return
  end

  local text = file:read("*a")
  file:close()
  if text == last_text then
    return
  end

  local chunk = load(text, "@" .. path, "t", {})
  if not chunk then
    return
  end
  local ok, result = pcall(chunk)
  if not ok or type(result) ~= "table" then
    return
  end

  local desired = {}
  for key, id in pairs(result) do
    if type(key) ~= "number" or type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then
      return
    end
    desired[id] = true
  end

  last_text = text
  apply(desired)
end

poll()

hl.timer(poll, { timeout = interval, type = "repeat" })

return M
