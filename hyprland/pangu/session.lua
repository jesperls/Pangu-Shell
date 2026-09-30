local data = os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")
local dir = data .. "/pangu"
local path = dir .. "/hypr-layout-state.lua"

local M = { data = {} }

local chunk = loadfile(path, "t", {})
if chunk then
  local ok, result = pcall(chunk)
  if ok and type(result) == "table" then
    M.data = result
  end
end

local instance = os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or ""
if M.data.instance ~= instance then -- Window IDs are reused across compositor instances.
  M.data.slots = nil
  M.data.weights = nil
end
M.data.instance = instance

function M.table(key)
  local value = M.data[key]
  if type(value) ~= "table" then
    value = {}
    M.data[key] = value
  end
  return value
end

local function encode(value, out)
  local t = type(value)
  if t == "number" then
    if value % 1 == 0 and value < 2 ^ 53 and value > -2 ^ 53 then
      out[#out + 1] = string.format("%.0f", value)
    else
      out[#out + 1] = string.format("%.14g", value)
    end
  elseif t == "string" then
    out[#out + 1] = string.format("%q", value)
  elseif t == "boolean" then
    out[#out + 1] = tostring(value)
  elseif t == "table" then
    out[#out + 1] = "{"
    for k, v in pairs(value) do
      local kt = type(k)
      if kt == "number" or kt == "string" then
        out[#out + 1] = "["
        encode(k, out)
        out[#out + 1] = "]="
        encode(v, out)
        out[#out + 1] = ","
      end
    end
    out[#out + 1] = "}"
  else
    out[#out + 1] = "nil"
  end
end

local written

function M.save()
  local out = {}
  encode(M.data, out)
  local text = "return " .. table.concat(out) .. "\n"
  if text == written then
    return
  end

  local tmp = path .. ".tmp"
  local file = io.open(tmp, "w")
  if not file then
    os.execute("mkdir -p '" .. dir:gsub("'", "'\\''") .. "'")
    file = io.open(tmp, "w")
  end
  if not file then
    return
  end
  local ok = file:write(text)
  local closed = file:close()
  if ok and closed and os.rename(tmp, path) then
    written = text
  else
    os.remove(tmp)
  end
end

return M
