local M = {}

---@param value any
---@return boolean
local function is_array(value)
  if type(value) ~= "table" then
    return false
  end

  local max = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or math.floor(key) ~= key then
      return false
    end
    if key > max then
      max = key
    end
  end

  for i = 1, max do
    if value[i] == nil then
      return false
    end
  end

  return true
end

---@param value any
---@return any
local function deep_copy(value)
  if type(value) ~= "table" then
    return value
  end
  return vim.deepcopy(value)
end

---@param value any
---@return string
local function stable_encode(value)
  local value_type = type(value)

  if value == nil then
    return "null"
  end
  if value_type == "boolean" then
    return value and "true" or "false"
  end
  if value_type == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      return "null"
    end
    return string.format("%.17g", value)
  end
  if value_type == "string" then
    return vim.json.encode(value)
  end

  if value_type ~= "table" then
    return vim.json.encode(tostring(value))
  end

  if is_array(value) then
    local encoded = {}
    for i = 1, #value do
      encoded[#encoded + 1] = stable_encode(value[i])
    end
    return "[" .. table.concat(encoded, ",") .. "]"
  end

  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b)
    local type_a = type(a)
    local type_b = type(b)
    if type_a == type_b then
      return tostring(a) < tostring(b)
    end
    return type_a < type_b
  end)

  local encoded = {}
  for _, key in ipairs(keys) do
    encoded[#encoded + 1] = ("%s:%s"):format(vim.json.encode(tostring(key)), stable_encode(value[key]))
  end
  return "{" .. table.concat(encoded, ",") .. "}"
end

---@param context table
---@param opts? table
---@return table
function M.build_payload(context, opts)
  opts = opts or {}

  return {
    context = deep_copy(context or {}),
    review_meta = deep_copy(opts.review_meta or {}),
    items = deep_copy(opts.items or {}),
    provenance = deep_copy(opts.provenance or {}),
  }
end

---@param payload table
---@return string
function M.serialize(payload)
  return stable_encode(payload)
end

return M
