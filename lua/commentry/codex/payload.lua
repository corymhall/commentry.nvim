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

---@param item table
---@return integer
local function item_line_start(item)
  local line_start = item.line_start or item.line_number
  if type(line_start) == "number" then
    return line_start
  end
  return 1
end

---@param item table
---@return integer
local function item_line_end(item)
  local line_end = item.line_end
  if type(line_end) == "number" then
    return line_end
  end
  return item_line_start(item)
end

---@param item table
---@return boolean
local function is_active_item(item)
  if type(item) ~= "table" then
    return false
  end
  if item.status == "unresolved" then
    return false
  end
  if item.stale == true or item.invalid == true then
    return false
  end
  return true
end

---@param threads any
---@return table<string, string>
local function thread_parent_by_comment(threads)
  local mapping = {}
  if type(threads) ~= "table" then
    return mapping
  end
  for _, thread in ipairs(threads) do
    if type(thread) == "table" and type(thread.id) == "string" and thread.id ~= "" then
      for _, comment_id in ipairs(thread.comment_ids or {}) do
        if type(comment_id) == "string" and comment_id ~= "" and mapping[comment_id] == nil then
          mapping[comment_id] = thread.id
        end
      end
    end
  end
  return mapping
end

---@param item table
---@param thread_parents table<string, string>
---@return table
local function project_item(item, thread_parents)
  local projected = {
    id = item.id,
    diff_id = item.diff_id or item.context_id,
    file_path = item.file_path,
    line_number = item.line_start or item.line_number,
    line_side = item.line_side,
    comment_type = item.comment_type or "note",
    body = item.body,
    status = item.status,
  }

  local thread_parent_id = item.thread_parent_id or item.thread_id or item.parent_id
  if thread_parent_id == nil and type(item.id) == "string" then
    thread_parent_id = thread_parents[item.id]
  end
  if thread_parent_id ~= nil then
    projected.thread_parent_id = thread_parent_id
  end

  return projected
end

---@param items any
---@param opts? table
---@return table
function M.extract_active_items(items, opts)
  opts = opts or {}
  if type(items) ~= "table" then
    return {}
  end

  local active = {}
  for _, item in ipairs(items) do
    if is_active_item(item) then
      active[#active + 1] = item
    end
  end

  table.sort(active, function(a, b)
    if a.file_path ~= b.file_path then
      return (a.file_path or "") < (b.file_path or "")
    end
    if a.line_side ~= b.line_side then
      return (a.line_side or "") < (b.line_side or "")
    end
    local a_start = item_line_start(a)
    local b_start = item_line_start(b)
    if a_start ~= b_start then
      return a_start < b_start
    end
    local a_end = item_line_end(a)
    local b_end = item_line_end(b)
    if a_end ~= b_end then
      return a_end < b_end
    end
    if (a.created_at or "") ~= (b.created_at or "") then
      return (a.created_at or "") < (b.created_at or "")
    end
    return (a.id or "") < (b.id or "")
  end)

  local projected = {}
  local thread_parents = thread_parent_by_comment(opts.threads)
  for _, item in ipairs(active) do
    projected[#projected + 1] = project_item(item, thread_parents)
  end
  return projected
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
  local items = M.extract_active_items(opts.items or {}, {
    threads = opts.threads,
  })

  return {
    context = deep_copy(context or {}),
    review_meta = deep_copy(opts.review_meta or {}),
    items = deep_copy(items),
    provenance = deep_copy(opts.provenance or {}),
  }
end

---@param payload table
---@return string
function M.serialize(payload)
  return stable_encode(payload)
end

return M
