local Config = require("commentry.config")
local Util = require("commentry.util")

local M = {}

local uv = vim.uv or vim.loop
local DEFAULT_COMMENT_TYPES = { "note", "suggestion", "issue", "praise" }

---@param value any
---@return boolean
local function is_integer(value)
  return type(value) == "number" and value > 0 and math.floor(value) == value
end

---@param value any
---@return boolean
local function is_array(value)
  if type(value) ~= "table" then
    return false
  end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" then
      return false
    end
    count = math.max(count, key)
  end
  for i = 1, count do
    if value[i] == nil then
      return false
    end
  end
  return true
end

---@param errors string[]
---@param msg string
local function push_error(errors, msg)
  errors[#errors + 1] = msg
end

---@param comment table
---@param errors string[]
---@param index number
---@param allowed_comment_types table<string, boolean>
---@param allowed_comment_type_list string[]
local function validate_comment(comment, errors, index, allowed_comment_types, allowed_comment_type_list)
  if type(comment) ~= "table" then
    push_error(errors, ("comments[%d] must be a table"):format(index))
    return
  end
  if type(comment.id) ~= "string" or comment.id == "" then
    push_error(errors, ("comments[%d].id must be a non-empty string"):format(index))
  end
  if type(comment.context_id) ~= "string" or comment.context_id == "" then
    push_error(errors, ("comments[%d].context_id must be a non-empty string"):format(index))
  end
  if type(comment.file_path) ~= "string" or comment.file_path == "" then
    push_error(errors, ("comments[%d].file_path must be a non-empty string"):format(index))
  end
  if not is_integer(comment.line_start) then
    push_error(errors, ("comments[%d].line_start must be a positive integer"):format(index))
  end
  if not is_integer(comment.line_end) then
    push_error(errors, ("comments[%d].line_end must be a positive integer"):format(index))
  end
  if is_integer(comment.line_start) and is_integer(comment.line_end) and comment.line_end < comment.line_start then
    push_error(errors, ("comments[%d].line_end must be >= line_start"):format(index))
  end
  if comment.line_side ~= "base" and comment.line_side ~= "head" then
    push_error(errors, ("comments[%d].line_side must be 'base' or 'head'"):format(index))
  end
  if type(comment.comment_type) ~= "string" or not allowed_comment_types[comment.comment_type] then
    push_error(
      errors,
      ("comments[%d].comment_type must be one of: %s"):format(index, table.concat(allowed_comment_type_list, ", "))
    )
  end
  if type(comment.body) ~= "string" or comment.body == "" then
    push_error(errors, ("comments[%d].body must be a non-empty string"):format(index))
  end
  if type(comment.created_at) ~= "string" or comment.created_at == "" then
    push_error(errors, ("comments[%d].created_at must be a non-empty string"):format(index))
  end
  if type(comment.updated_at) ~= "string" or comment.updated_at == "" then
    push_error(errors, ("comments[%d].updated_at must be a non-empty string"):format(index))
  end
  if comment.status ~= nil and type(comment.status) ~= "string" then
    push_error(errors, ("comments[%d].status must be a string when provided"):format(index))
  end
  if comment.line_content ~= nil and type(comment.line_content) ~= "string" then
    push_error(errors, ("comments[%d].line_content must be a string when provided"):format(index))
  end
end

---@param thread table
---@param errors string[]
---@param index number
local function validate_thread(thread, errors, index)
  if type(thread) ~= "table" then
    push_error(errors, ("threads[%d] must be a table"):format(index))
    return
  end
  if type(thread.id) ~= "string" or thread.id == "" then
    push_error(errors, ("threads[%d].id must be a non-empty string"):format(index))
  end
  if type(thread.context_id) ~= "string" or thread.context_id == "" then
    push_error(errors, ("threads[%d].context_id must be a non-empty string"):format(index))
  end
  if type(thread.file_path) ~= "string" or thread.file_path == "" then
    push_error(errors, ("threads[%d].file_path must be a non-empty string"):format(index))
  end
  if not is_integer(thread.line_start) then
    push_error(errors, ("threads[%d].line_start must be a positive integer"):format(index))
  end
  if not is_integer(thread.line_end) then
    push_error(errors, ("threads[%d].line_end must be a positive integer"):format(index))
  end
  if is_integer(thread.line_start) and is_integer(thread.line_end) and thread.line_end < thread.line_start then
    push_error(errors, ("threads[%d].line_end must be >= line_start"):format(index))
  end
  if thread.line_side ~= "base" and thread.line_side ~= "head" then
    push_error(errors, ("threads[%d].line_side must be 'base' or 'head'"):format(index))
  end
  if not is_array(thread.comment_ids or {}) then
    push_error(errors, ("threads[%d].comment_ids must be an array"):format(index))
  else
    for comment_index, comment_id in ipairs(thread.comment_ids) do
      if type(comment_id) ~= "string" or comment_id == "" then
        push_error(errors, ("threads[%d].comment_ids[%d] must be a non-empty string"):format(index, comment_index))
      end
    end
  end
end

---@param file_reviews table|nil
---@param errors string[]
local function validate_file_reviews(file_reviews, errors)
  if type(file_reviews) ~= "table" then
    push_error(errors, "store.file_reviews must be a table")
    return
  end
  if is_array(file_reviews) then
    push_error(errors, "store.file_reviews must be a map of file path to boolean")
    return
  end
  for file_path, reviewed in pairs(file_reviews) do
    if type(file_path) ~= "string" or file_path == "" then
      push_error(errors, "store.file_reviews keys must be non-empty strings")
    end
    if type(reviewed) ~= "boolean" then
      push_error(errors, ("store.file_reviews[%s] must be a boolean"):format(tostring(file_path)))
    end
  end
end

---@return table<string, boolean>, string[]
local function allowed_comment_types()
  local seen = {}
  local allowed = {}
  local list = {}

  local function add_type(value)
    if type(value) ~= "string" or value == "" or seen[value] then
      return
    end
    seen[value] = true
    allowed[value] = true
    list[#list + 1] = value
  end

  for _, value in ipairs(DEFAULT_COMMENT_TYPES) do
    add_type(value)
  end
  if type(Config.comment_types) == "table" then
    for _, value in ipairs(Config.comment_types) do
      add_type(value)
    end
  end

  return allowed, list
end

---@param store table
---@return boolean, string[]
function M.validate(store)
  local errors = {}
  if type(store) ~= "table" then
    push_error(errors, "store must be a table")
    return false, errors
  end

  if type(store.project_root) ~= "string" or store.project_root == "" then
    push_error(errors, "store.project_root must be a non-empty string")
  end
  if type(store.context_id) ~= "string" or store.context_id == "" then
    push_error(errors, "store.context_id must be a non-empty string")
  end
  if not is_array(store.comments or {}) then
    push_error(errors, "store.comments must be an array")
  end
  if not is_array(store.threads or {}) then
    push_error(errors, "store.threads must be an array")
  end
  validate_file_reviews(store.file_reviews, errors)

  local comment_type_set, comment_type_list = allowed_comment_types()

  if is_array(store.comments or {}) then
    for index, comment in ipairs(store.comments or {}) do
      validate_comment(comment, errors, index, comment_type_set, comment_type_list)
    end
  end

  if is_array(store.threads or {}) then
    for index, thread in ipairs(store.threads or {}) do
      validate_thread(thread, errors, index)
    end
  end

  return #errors == 0, errors
end

---@param context_id string
---@return string
local function normalize_context_id(context_id)
  return context_id:gsub("[^%w%._%-]", "_")
end

---@param project_root string
---@param context_id string
---@param filename? string
---@return string|nil, string|nil
function M.path_for_context(project_root, context_id, filename)
  if type(project_root) ~= "string" or project_root == "" then
    return nil, "project_root is required"
  end
  if type(context_id) ~= "string" or context_id == "" then
    return nil, "context_id is required"
  end

  local root = vim.fs.normalize(project_root)
  local resolved = uv.fs_realpath(root) or root
  local stat = uv.fs_stat(resolved)
  if not stat or stat.type ~= "directory" then
    return nil, "project_root is not a directory"
  end

  local name = filename or Config.store.filename
  if type(name) ~= "string" or name == "" then
    return nil, "filename is required"
  end

  local context_dir = normalize_context_id(context_id)
  local base = vim.fs.joinpath(resolved, ".commentry", "contexts", context_dir)
  return vim.fs.joinpath(base, name), nil
end

---@param path string
---@return table|nil, string|string[]|nil
function M.read(path)
  if type(path) ~= "string" or path == "" then
    return nil, "path is required"
  end
  local stat = uv.fs_stat(path)
  if not stat then
    return nil, "not_found"
  end
  local ok, content = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, "read_failed"
  end
  local json = table.concat(content, "\n")
  local ok_decode, data = pcall(vim.json.decode, json)
  if not ok_decode then
    return nil, "invalid_json"
  end
  local valid, errors = M.validate(data)
  if not valid then
    return nil, errors
  end
  return data, nil
end

---@param path string
---@param store table
---@return boolean, string|string[]|nil
function M.write(path, store)
  if type(path) ~= "string" or path == "" then
    return false, "path is required"
  end
  local valid, errors = M.validate(store)
  if not valid then
    return false, errors
  end

  local ok, encoded = pcall(vim.json.encode, store)
  if not ok then
    Util.error("Failed to encode comment store")
    return false, "encode_failed"
  end

  local parent = vim.fn.fnamemodify(path, ":h")
  if parent ~= "" then
    vim.fn.mkdir(parent, "p")
  end

  local wrote, result = pcall(vim.fn.writefile, { encoded }, path)
  if not wrote or result ~= 0 then
    return false, "write_failed"
  end

  return true, nil
end

return M
