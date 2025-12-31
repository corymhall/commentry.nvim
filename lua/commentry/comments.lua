local M = {}

local uv = vim.uv or vim.loop
local seeded = false

---@param value any
---@return boolean
local function is_integer(value)
  return type(value) == "number" and value > 0 and math.floor(value) == value
end

local function seed_rng()
  if seeded then
    return
  end
  seeded = true
  local seed = tonumber(tostring(uv.hrtime()):sub(-9)) or os.time()
  math.randomseed(seed)
end

---@return string
local function timestamp()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

---@param file_path string
---@param line_number integer
---@param line_side string
---@return boolean, string|nil
local function validate_anchor(file_path, line_number, line_side)
  if type(file_path) ~= "string" or file_path == "" then
    return false, "file_path is required"
  end
  if not is_integer(line_number) then
    return false, "line_number must be a positive integer"
  end
  if line_side ~= "base" and line_side ~= "head" then
    return false, "line_side must be 'base' or 'head'"
  end
  return true, nil
end

---@param prefix? string
---@return string
function M.new_id(prefix)
  seed_rng()
  return ("%s-%s-%06d"):format(prefix or "c", uv.hrtime(), math.random(0, 999999))
end

---@class commentry.Anchor
---@field file_path string
---@field line_number integer
---@field line_side '"base"'|'"head"'

---@param file_path string
---@param line_number integer
---@param line_side '"base"'|'"head"'
---@return commentry.Anchor|nil, string|nil
function M.build_anchor(file_path, line_number, line_side)
  local ok, err = validate_anchor(file_path, line_number, line_side)
  if not ok then
    return nil, err
  end
  return {
    file_path = file_path,
    line_number = line_number,
    line_side = line_side,
  }, nil
end

---@param anchor commentry.Anchor
---@return string|nil, string|nil
function M.anchor_key(anchor)
  if type(anchor) ~= "table" then
    return nil, "anchor is required"
  end
  local ok, err = validate_anchor(anchor.file_path, anchor.line_number, anchor.line_side)
  if not ok then
    return nil, err
  end
  return ("%s|%s|%d"):format(anchor.file_path, anchor.line_side, anchor.line_number), nil
end

---@param diff_id string
---@param anchor commentry.Anchor
---@return string|nil, string|nil
function M.thread_id(diff_id, anchor)
  if type(diff_id) ~= "string" or diff_id == "" then
    return nil, "diff_id is required"
  end
  local key, err = M.anchor_key(anchor)
  if not key then
    return nil, err
  end
  return ("t-%s-%s"):format(diff_id, key), nil
end

---@class commentry.DraftComment
---@field id string
---@field diff_id string
---@field file_path string
---@field line_number integer
---@field line_side '"base"'|'"head"'
---@field body string
---@field created_at string
---@field updated_at string
---@field status? string

---@class commentry.CommentInput
---@field id? string
---@field created_at? string
---@field updated_at? string
---@field status? string

---@param diff_id string
---@param anchor commentry.Anchor
---@param body string
---@param opts? commentry.CommentInput
---@return commentry.DraftComment|nil, string|nil
function M.new_comment(diff_id, anchor, body, opts)
  opts = opts or {}
  if type(diff_id) ~= "string" or diff_id == "" then
    return nil, "diff_id is required"
  end
  if type(body) ~= "string" or body == "" then
    return nil, "body is required"
  end
  local ok, err = validate_anchor(anchor.file_path, anchor.line_number, anchor.line_side)
  if not ok then
    return nil, err
  end
  local created_at = opts.created_at or timestamp()
  local updated_at = opts.updated_at or created_at
  return {
    id = opts.id or M.new_id("c"),
    diff_id = diff_id,
    file_path = anchor.file_path,
    line_number = anchor.line_number,
    line_side = anchor.line_side,
    body = body,
    created_at = created_at,
    updated_at = updated_at,
    status = opts.status,
  }, nil
end

---@param comment commentry.DraftComment
---@param body string
---@return commentry.DraftComment|nil, string|nil
function M.update_body(comment, body)
  if type(comment) ~= "table" then
    return nil, "comment is required"
  end
  if type(body) ~= "string" or body == "" then
    return nil, "body is required"
  end
  local updated = vim.deepcopy(comment)
  updated.body = body
  updated.updated_at = timestamp()
  return updated, nil
end

---@class commentry.CommentThread
---@field id string
---@field diff_id string
---@field file_path string
---@field line_number integer
---@field line_side '"base"'|'"head"'
---@field comment_ids string[]

---@param diff_id string
---@param anchor commentry.Anchor
---@param comment_ids? string[]
---@return commentry.CommentThread|nil, string|nil
function M.new_thread(diff_id, anchor, comment_ids)
  if type(diff_id) ~= "string" or diff_id == "" then
    return nil, "diff_id is required"
  end
  local ok, err = validate_anchor(anchor.file_path, anchor.line_number, anchor.line_side)
  if not ok then
    return nil, err
  end
  local id, id_err = M.thread_id(diff_id, anchor)
  if not id then
    return nil, id_err
  end
  return {
    id = id,
    diff_id = diff_id,
    file_path = anchor.file_path,
    line_number = anchor.line_number,
    line_side = anchor.line_side,
    comment_ids = comment_ids or {},
  }, nil
end

return M
