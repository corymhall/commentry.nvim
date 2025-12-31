local Config = require("commentry.config")
local Util = require("commentry.util")

local M = {}

local uv = vim.uv or vim.loop

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
local function validate_comment(comment, errors, index)
  if type(comment) ~= "table" then
    push_error(errors, ("comments[%d] must be a table"):format(index))
    return
  end
  if type(comment.id) ~= "string" or comment.id == "" then
    push_error(errors, ("comments[%d].id must be a non-empty string"):format(index))
  end
  if type(comment.diff_id) ~= "string" or comment.diff_id == "" then
    push_error(errors, ("comments[%d].diff_id must be a non-empty string"):format(index))
  end
  if type(comment.file_path) ~= "string" or comment.file_path == "" then
    push_error(errors, ("comments[%d].file_path must be a non-empty string"):format(index))
  end
  if not is_integer(comment.line_number) then
    push_error(errors, ("comments[%d].line_number must be a positive integer"):format(index))
  end
  if comment.line_side ~= "base" and comment.line_side ~= "head" then
    push_error(errors, ("comments[%d].line_side must be 'base' or 'head'"):format(index))
  end
  if type(comment.body) ~= "string" or comment.body == "" then
    push_error(errors, ("comments[%d].body must be a non-empty string"):format(index))
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
  if type(thread.diff_id) ~= "string" or thread.diff_id == "" then
    push_error(errors, ("threads[%d].diff_id must be a non-empty string"):format(index))
  end
  if type(thread.file_path) ~= "string" or thread.file_path == "" then
    push_error(errors, ("threads[%d].file_path must be a non-empty string"):format(index))
  end
  if not is_integer(thread.line_number) then
    push_error(errors, ("threads[%d].line_number must be a positive integer"):format(index))
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
  if type(store.diff_id) ~= "string" or store.diff_id == "" then
    push_error(errors, "store.diff_id must be a non-empty string")
  end
  if not is_array(store.comments or {}) then
    push_error(errors, "store.comments must be an array")
  end
  if not is_array(store.threads or {}) then
    push_error(errors, "store.threads must be an array")
  end

  if is_array(store.comments or {}) then
    for index, comment in ipairs(store.comments) do
      validate_comment(comment, errors, index)
    end
  end

  if is_array(store.threads or {}) then
    for index, thread in ipairs(store.threads) do
      validate_thread(thread, errors, index)
    end
  end

  return #errors == 0, errors
end

---@param project_root string
---@param filename? string
---@return string|nil, string|nil
function M.path_for_project(project_root, filename)
  if type(project_root) ~= "string" or project_root == "" then
    return nil, "project_root is required"
  end

  local stat = uv.fs_stat(project_root)
  if not stat or stat.type ~= "directory" then
    return nil, "project_root is not a directory"
  end

  local name = filename or Config.store.filename
  if type(name) ~= "string" or name == "" then
    return nil, "filename is required"
  end

  local root = vim.fs.normalize(project_root)
  local base = vim.fs.joinpath(root, ".commentry")
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

  local wrote = pcall(vim.fn.writefile, { encoded }, path)
  if not wrote then
    return false, "write_failed"
  end

  return true, nil
end

return M
