local M = {}
local uv = vim.uv or vim.loop

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

---@param root any
---@return string|nil
local function normalize_root(root)
  if type(root) ~= "string" or root == "" then
    return nil
  end
  local normalized = vim.fs.normalize(root)
  if normalized:sub(-5) == "/.git" then
    normalized = normalized:sub(1, -6)
  end
  if normalized == "" then
    return nil
  end
  local resolved = uv and uv.fs_realpath(normalized) or nil
  return vim.fs.normalize(resolved or normalized)
end

---@param path string
---@return boolean
local function is_absolute_path(path)
  if path == "" then
    return false
  end
  if path:sub(1, 1) == "/" then
    return true
  end
  if path:match("^%a:[/\\]") then
    return true
  end
  return false
end

---@param path any
---@param root string|nil
---@return string|nil
local function normalize_path(path, root)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local normalized = vim.fs.normalize(path)
  if not is_absolute_path(normalized) then
    return normalized
  end
  if not root then
    return nil
  end
  local rel = vim.fs.relpath(root, normalized)
  if type(rel) ~= "string" or rel == "" or rel:sub(1, 3) == "../" or rel == ".." then
    return nil
  end
  return rel
end

---@param provenance table
---@param context table
---@return table
local function normalize_provenance(provenance, context)
  local root = normalize_root(
    provenance.repo_root or provenance.root or provenance.project_root or context.root or context.git_root
  )
  local normalized = {}

  local function copy_value(key, value)
    if key == "root" or key == "repo_root" or key == "project_root" then
      return root
    end
    if type(value) == "string" then
      if key == "file" or key == "path" or key == "file_path" then
        return normalize_path(value, root)
      end
      return value
    end
    if type(value) ~= "table" then
      return value
    end
    if is_array(value) then
      local out = {}
      local path_list = key == "files" or key == "paths"
      for _, entry in ipairs(value) do
        if path_list and type(entry) == "string" then
          local normalized_entry = normalize_path(entry, root)
          if normalized_entry then
            out[#out + 1] = normalized_entry
          end
        else
          out[#out + 1] = deep_copy(entry)
        end
      end
      return out
    end
    local out = {}
    for child_key, child_value in pairs(value) do
      local next_value = copy_value(child_key, child_value)
      if next_value ~= nil then
        out[child_key] = next_value
      end
    end
    return out
  end

  for key, value in pairs(provenance) do
    local next_value = copy_value(key, value)
    if next_value ~= nil then
      normalized[key] = next_value
    end
  end

  return normalized
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
---@param root string|nil
---@return table
local function project_item(item, thread_parents, root)
  local line_start = item.line_start or item.line_number
  local line_end = item.line_end or line_start
  local projected = {
    id = item.id,
    diff_id = item.diff_id or item.context_id,
    file_path = normalize_path(item.file_path, root),
    line_number = line_start,
    line_start = line_start,
    line_end = line_end,
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
  local root = normalize_root(opts.root or opts.repo_root or opts.project_root or opts.git_root)
  local thread_parents = thread_parent_by_comment(opts.threads)
  for _, item in ipairs(active) do
    projected[#projected + 1] = project_item(item, thread_parents, root)
  end
  return projected
end

---@param context table
---@return table
local function normalize_context(context)
  if type(context) ~= "table" then
    return {}
  end

  local normalized = deep_copy(context)
  local root = normalize_root(normalized.root or normalized.repo_root or normalized.project_root or normalized.git_root)

  for _, key in ipairs({ "root", "repo_root", "project_root", "git_root" }) do
    if normalized[key] ~= nil then
      normalized[key] = root
    end
  end
  if normalized.root == nil and root then
    normalized.root = root
  end

  for _, key in ipairs({ "file_path", "path" }) do
    normalized[key] = normalize_path(normalized[key], root)
  end

  return normalized
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
  context = context or {}
  local items = M.extract_active_items(opts.items or {}, {
    threads = opts.threads,
    root = context.root or context.repo_root or context.project_root or context.git_root,
  })

  return {
    context = normalize_context(context),
    review_meta = deep_copy(opts.review_meta or {}),
    items = deep_copy(items),
    provenance = normalize_provenance(deep_copy(opts.provenance or {}), context),
  }
end

---@param payload table
---@return string
function M.serialize(payload)
  return stable_encode(payload)
end

---@param value any
---@return string[]
local function normalize_string_list(value)
  if type(value) ~= "table" then
    return {}
  end
  local out = {}
  for _, entry in ipairs(value) do
    if type(entry) == "string" and entry ~= "" then
      out[#out + 1] = entry
    end
  end
  return out
end

---@param payload table
---@return string
function M.render_compact(payload)
  payload = type(payload) == "table" and payload or {}
  local context = type(payload.context) == "table" and payload.context or {}
  local review_meta = type(payload.review_meta) == "table" and payload.review_meta or {}
  local provenance = type(payload.provenance) == "table" and payload.provenance or {}
  local items = type(payload.items) == "table" and payload.items or {}

  local mode = review_meta.mode or context.mode or "working_tree"
  local context_id = context.context_id or ""
  local root = context.root or provenance.root or ""
  local revisions = normalize_string_list(review_meta.revisions or context.revisions)

  local lines = {
    "COMMENTRY_REVIEW_V1",
    ("mode: %s"):format(mode),
  }
  if context_id ~= "" then
    lines[#lines + 1] = ("context: %s"):format(context_id)
  end
  if root ~= "" then
    lines[#lines + 1] = ("root: %s"):format(root)
  end
  if #revisions > 0 then
    lines[#lines + 1] = ("revisions: %s"):format(table.concat(revisions, ", "))
  end

  local anchors = review_meta.revision_anchors or context.revision_anchors
  if type(anchors) == "table" and #anchors > 0 then
    local anchor_labels = {}
    for _, anchor in ipairs(anchors) do
      if type(anchor) == "table" then
        local token = anchor.token or "?"
        if type(anchor.commit) == "string" and anchor.commit ~= "" then
          anchor_labels[#anchor_labels + 1] = ("%s=%s"):format(token, anchor.commit:sub(1, 12))
        elseif type(anchor.canonical) == "string" and anchor.canonical ~= "" then
          anchor_labels[#anchor_labels + 1] = ("%s=%s"):format(token, anchor.canonical)
        end
      end
    end
    if #anchor_labels > 0 then
      lines[#lines + 1] = ("anchors: %s"):format(table.concat(anchor_labels, ", "))
    end
  end

  lines[#lines + 1] = ("items: %d"):format(#items)

  for index, item in ipairs(items) do
    if type(item) == "table" then
      local file_path = item.file_path or "?"
      local line_start = item.line_start or item.line_number
      local line_end = item.line_end or line_start
      local line = "?"
      if type(line_start) == "number" then
        if type(line_end) == "number" and line_end > line_start then
          line = ("%d-%d"):format(line_start, line_end)
        else
          line = tostring(line_start)
        end
      end
      local side = item.line_side or "head"
      local comment_type = item.comment_type or "note"
      local id = item.id or ("item-%d"):format(index)
      local header = ("%d. %s:%s [%s/%s] id=%s"):format(index, file_path, line, side, comment_type, id)
      lines[#lines + 1] = header
      if type(item.thread_parent_id) == "string" and item.thread_parent_id ~= "" then
        lines[#lines + 1] = ("   thread=%s"):format(item.thread_parent_id)
      end
      local body = type(item.body) == "string" and item.body or ""
      local body_lines = vim.split(body, "\n", { plain = true })
      if #body_lines == 0 then
        body_lines = { "" }
      end
      for _, body_line in ipairs(body_lines) do
        lines[#lines + 1] = ("   | %s"):format(body_line)
      end
    end
  end

  return table.concat(lines, "\n")
end

return M
