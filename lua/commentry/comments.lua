local Diffview = require("commentry.diffview")
local Config = require("commentry.config")
local Store = require("commentry.store")
local Util = require("commentry.util")

local M = {}

local uv = vim.uv or vim.loop
local seeded = false

local state = {
  diffs = {},
}
local current_context

local ROOT_CANDIDATE_KEYS = { "git_root", "toplevel", "root", "cwd", "path" }
local DEFAULT_COMMENT_TYPES = { "note", "suggestion", "issue", "praise" }

---@param root string
---@return string|nil
local function normalize_root_candidate(root)
  if type(root) ~= "string" or root == "" then
    return nil
  end
  local normalized = vim.fs.normalize(root)
  if normalized:match("[/\\]%.git$") then
    normalized = vim.fs.normalize(vim.fn.fnamemodify(normalized, ":h"))
  end
  local resolved = uv.fs_realpath(normalized) or normalized
  local stat = uv.fs_stat(resolved)
  if stat and stat.type == "directory" then
    return vim.fs.normalize(resolved)
  end
  return nil
end

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

---@return string[]
local function comment_type_choices()
  if type(Config.comment_types) ~= "table" or #Config.comment_types == 0 then
    return vim.deepcopy(DEFAULT_COMMENT_TYPES)
  end
  local seen = {}
  local choices = {}
  for _, item in ipairs(Config.comment_types) do
    if type(item) == "string" and item ~= "" and not seen[item] then
      seen[item] = true
      choices[#choices + 1] = item
    end
  end
  if #choices == 0 then
    return vim.deepcopy(DEFAULT_COMMENT_TYPES)
  end
  return choices
end

---@param comment_type string
---@return boolean
local function is_valid_comment_type(comment_type)
  if type(comment_type) ~= "string" or comment_type == "" then
    return false
  end
  for _, candidate in ipairs(comment_type_choices()) do
    if candidate == comment_type then
      return true
    end
  end
  return false
end

---@return string
local function default_comment_type()
  if is_valid_comment_type(Config.default_comment_type) then
    return Config.default_comment_type
  end
  return comment_type_choices()[1]
end

---@param diff_id string
---@return table
local function diff_state(diff_id)
  if not state.diffs[diff_id] then
    state.diffs[diff_id] = {
      comments = {},
      threads = {},
      file_reviews = {},
      comments_by_id = {},
      threads_by_id = {},
      dirty = false,
      selected_comment_type = nil,
    }
  end
  return state.diffs[diff_id]
end

---@param diff_id string
---@return string
local function selected_comment_type(diff_id)
  local dstate = diff_state(diff_id)
  if is_valid_comment_type(dstate.selected_comment_type) then
    return dstate.selected_comment_type
  end
  local fallback = default_comment_type()
  dstate.selected_comment_type = fallback
  return fallback
end

---@param diff_id string
local function mark_dirty(diff_id)
  diff_state(diff_id).dirty = true
end

---@param diff_id string
local function clear_dirty(diff_id)
  diff_state(diff_id).dirty = false
end

---@param diff_id string
---@return boolean
local function is_dirty(diff_id)
  return diff_state(diff_id).dirty == true
end

---@param view? table
---@return string
local function diff_id_for_view(view)
  if type(Diffview.resolve_review_context) == "function" then
    local context = Diffview.resolve_review_context(nil, view)
    if type(context) == "table" and type(context.context_id) == "string" and context.context_id ~= "" then
      return context.context_id
    end
  end
  if type(view) == "table" then
    for _, key in ipairs(ROOT_CANDIDATE_KEYS) do
      local resolved = normalize_root_candidate(view[key])
      if resolved then
        return resolved
      end
    end
  end
  local id = nil
  if type(view) == "table" then
    id = view.id or view.tabpage or view.tabnr or view.view_id
  end
  if not id then
    id = vim.api.nvim_get_current_tabpage()
  end
  return tostring(id)
end

---@param view? table
---@return string|nil
local function project_root_for_view(view)
  if type(Diffview.resolve_review_context) == "function" then
    local context = Diffview.resolve_review_context(nil, view)
    if type(context) == "table" and type(context.root) == "string" and context.root ~= "" then
      return context.root
    end
  end
  if type(view) == "table" then
    for _, key in ipairs(ROOT_CANDIDATE_KEYS) do
      local resolved = normalize_root_candidate(view[key])
      if resolved then
        return resolved
      end
    end
  end
  local output = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 then
    return nil
  end
  local root = output[1]
  return normalize_root_candidate(root)
end

---@param view? table
---@return string|nil, string|nil
function M.context_id_for_view(view)
  if type(Diffview.resolve_review_context) == "function" then
    local context, err = Diffview.resolve_review_context(nil, view)
    if not context then
      return nil, err
    end
    if type(context.context_id) ~= "string" or context.context_id == "" then
      return nil, "context_id_unavailable"
    end
    return context.context_id, nil
  end
  return diff_id_for_view(view), nil
end

---@param view? table
---@param err_msg string
---@return string|nil
local function require_context_id(view, err_msg)
  local context_id, context_err = M.context_id_for_view(view)
  if context_id then
    return context_id
  end
  if err_msg ~= "" then
    Util.warn(context_err or err_msg)
  end
  return nil
end

---@param context table
---@return commentry.Anchor|nil, string|nil
local function anchor_from_context(context)
  if type(context) ~= "table" then
    return nil, "diffview context is required"
  end
  return M.build_anchor(context.file_path, context.line_number, context.line_side, context.line_end)
end

---@param item table
---@return integer|nil
local function line_start_for(item)
  if type(item) ~= "table" then
    return nil
  end
  local line_start = item.line_start or item.line_number
  if type(line_start) ~= "number" then
    return nil
  end
  return line_start
end

---@param item table
---@return integer|nil
local function line_end_for(item)
  if type(item) ~= "table" then
    return nil
  end
  local line_start = line_start_for(item)
  local line_end = item.line_end or line_start
  if type(line_end) ~= "number" then
    return nil
  end
  return line_end
end

---@param item table
---@param line_number integer
---@return boolean
local function contains_line(item, line_number)
  local line_start = line_start_for(item)
  local line_end = line_end_for(item)
  return type(line_start) == "number"
    and type(line_end) == "number"
    and type(line_number) == "number"
    and line_number >= line_start
    and line_number <= line_end
end

---@param diff_id string
---@param anchor commentry.Anchor
---@return commentry.CommentThread|nil, string|nil
local function ensure_thread(diff_id, anchor)
  local thread_id, err = M.thread_id(diff_id, anchor)
  if not thread_id then
    return nil, err
  end
  local dstate = diff_state(diff_id)
  local thread = dstate.threads_by_id[thread_id]
  if thread then
    return thread, nil
  end
  local created, thread_err = M.new_thread(diff_id, anchor)
  if not created then
    return nil, thread_err
  end
  dstate.threads_by_id[thread_id] = created
  dstate.threads[#dstate.threads + 1] = created
  return created, nil
end

---@param dstate table
---@param comment commentry.DraftComment
local function upsert_comment(dstate, comment)
  dstate.comments_by_id[comment.id] = comment
  for index, existing in ipairs(dstate.comments) do
    if existing.id == comment.id then
      dstate.comments[index] = comment
      return
    end
  end
  dstate.comments[#dstate.comments + 1] = comment
end

---@param dstate table
---@param comment_id string
local function remove_comment(dstate, comment_id)
  dstate.comments_by_id[comment_id] = nil
  for index = #dstate.comments, 1, -1 do
    if dstate.comments[index].id == comment_id then
      table.remove(dstate.comments, index)
      break
    end
  end
end

---@param thread commentry.CommentThread
---@param comment_id string
local function remove_from_thread(thread, comment_id)
  for index = #thread.comment_ids, 1, -1 do
    if thread.comment_ids[index] == comment_id then
      table.remove(thread.comment_ids, index)
      break
    end
  end
end

---@param dstate table
---@param thread commentry.CommentThread
local function maybe_drop_thread(dstate, thread)
  if #thread.comment_ids > 0 then
    return
  end
  dstate.threads_by_id[thread.id] = nil
  for index = #dstate.threads, 1, -1 do
    if dstate.threads[index].id == thread.id then
      table.remove(dstate.threads, index)
      break
    end
  end
end

---@param dstate table
---@param comment_id string
local function remove_comment_from_threads(dstate, comment_id)
  for _, thread in ipairs(dstate.threads) do
    remove_from_thread(thread, comment_id)
    maybe_drop_thread(dstate, thread)
  end
end

---@param bufnr integer
---@param line_number integer
---@return string|nil
local function line_text_at(bufnr, line_number)
  if type(bufnr) ~= "number" or line_number < 1 then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, line_number - 1, line_number, false)
  if type(lines) ~= "table" or #lines == 0 then
    return nil
  end
  return lines[1]
end

---@param diff_id string
---@param store table
local function apply_store(diff_id, store)
  local dstate = diff_state(diff_id)
  dstate.comments = {}
  dstate.threads = {}
  dstate.file_reviews = {}
  dstate.comments_by_id = {}
  dstate.threads_by_id = {}

  if type(store.file_reviews) == "table" then
    dstate.file_reviews = vim.deepcopy(store.file_reviews)
  end

  if type(store.comments) == "table" then
    for _, comment in ipairs(store.comments) do
      if type(comment) == "table" then
        local line_start = comment.line_start or comment.line_number
        local line_end = comment.line_end or line_start
        local context_id = comment.context_id or comment.diff_id
        local runtime_comment = {
          id = comment.id,
          diff_id = context_id,
          file_path = comment.file_path,
          line_number = line_start,
          line_side = comment.line_side,
          body = comment.body,
          created_at = comment.created_at or timestamp(),
          updated_at = comment.updated_at or comment.created_at or timestamp(),
          status = comment.status,
          line_content = comment.line_content,
          comment_type = comment.comment_type or "note",
          line_start = line_start,
          line_end = line_end,
        }
        upsert_comment(dstate, runtime_comment)
      end
    end
  end

  if type(store.threads) == "table" then
    for _, thread in ipairs(store.threads) do
      if type(thread) == "table" and type(thread.id) == "string" then
        local line_start = thread.line_start or thread.line_number
        local line_end = thread.line_end or line_start
        local context_id = thread.context_id or thread.diff_id
        local runtime_thread = {
          id = thread.id,
          diff_id = context_id,
          file_path = thread.file_path,
          line_number = line_start,
          line_side = thread.line_side,
          comment_ids = vim.deepcopy(thread.comment_ids or {}),
          line_start = line_start,
          line_end = line_end,
        }
        dstate.threads_by_id[thread.id] = runtime_thread
        dstate.threads[#dstate.threads + 1] = runtime_thread
        local canonical_id, canonical_err = M.thread_id(context_id, runtime_thread)
        if canonical_id then
          dstate.threads_by_id[canonical_id] = runtime_thread
        elseif canonical_err then
          Util.debug("Unable to build canonical thread id while loading", canonical_err)
        end
      end
    end
  end
end

---@param context_id string
---@param comment table
---@return table
local function runtime_comment_to_store(context_id, comment)
  local line_start = comment.line_start or comment.line_number
  local line_end = comment.line_end or line_start
  return {
    id = comment.id,
    context_id = context_id,
    file_path = comment.file_path,
    line_start = line_start,
    line_end = line_end,
    line_side = comment.line_side,
    comment_type = comment.comment_type or "note",
    body = comment.body,
    created_at = comment.created_at,
    updated_at = comment.updated_at,
    status = comment.status,
    line_content = comment.line_content,
  }
end

---@param context_id string
---@param thread table
---@return table
local function runtime_thread_to_store(context_id, thread)
  local line_start = thread.line_start or thread.line_number
  local line_end = thread.line_end or line_start
  return {
    id = thread.id,
    context_id = context_id,
    file_path = thread.file_path,
    line_start = line_start,
    line_end = line_end,
    line_side = thread.line_side,
    comment_ids = vim.deepcopy(thread.comment_ids or {}),
  }
end

---@param project_root string
---@param context_id string
---@return string|nil, string|nil
local function path_for_context(project_root, context_id)
  if type(Store.path_for_context) == "function" then
    return Store.path_for_context(project_root, context_id)
  end
  return Store.path_for_project(project_root)
end

---@param diff_id string
---@param project_root string
---@param context_id string
---@return boolean, string|string[]|nil
local function save_store(diff_id, project_root, context_id)
  local path, path_err = path_for_context(project_root, context_id)
  if not path then
    return false, path_err or "store_path_failed"
  end

  local dstate = diff_state(diff_id)
  local comments = {}
  for _, comment in ipairs(dstate.comments) do
    comments[#comments + 1] = runtime_comment_to_store(context_id, comment)
  end
  local threads = {}
  for _, thread in ipairs(dstate.threads) do
    threads[#threads + 1] = runtime_thread_to_store(context_id, thread)
  end
  local store = {
    project_root = project_root,
    context_id = context_id,
    comments = comments,
    threads = threads,
    file_reviews = vim.deepcopy(dstate.file_reviews or {}),
  }

  return Store.write(path, store)
end

---@param diff_id string
---@param view table
---@param failure_msg string
---@return boolean
local function persist_for_view(diff_id, view, failure_msg)
  local root = project_root_for_view(view)
  if not root then
    Util.warn("Unable to resolve project root for comment store")
    return false
  end
  local context_id = require_context_id(view, "Unable to resolve review context")
  if not context_id then
    return false
  end
  local ok, save_err = save_store(diff_id, root, context_id)
  if not ok then
    Util.warn(save_err or failure_msg)
    return false
  end
  clear_dirty(diff_id)
  return true
end

---@param diff_id string
---@param context table
---@return boolean
local function reconcile_for_context(diff_id, context)
  if type(context) ~= "table" or type(context.bufnr) ~= "number" then
    return false
  end
  local line_count = vim.api.nvim_buf_line_count(context.bufnr)
  local dstate = diff_state(diff_id)
  local unresolved = {}
  local hydrated = 0
  for _, comment in ipairs(dstate.comments) do
    local in_target = comment.file_path == context.file_path and comment.line_side == context.line_side
    local anchor_line = line_start_for(comment)
    local in_range = type(anchor_line) == "number" and anchor_line >= 1 and anchor_line <= line_count
    local missing_line_content = in_target and in_range and type(comment.line_content) ~= "string"
    local mismatched = false
    if missing_line_content then
      local current = line_text_at(context.bufnr, anchor_line)
      if type(current) == "string" then
        comment.line_content = current
        hydrated = hydrated + 1
      end
    elseif in_target and in_range then
      local current = line_text_at(context.bufnr, anchor_line)
      mismatched = current ~= nil and current ~= comment.line_content
    end
    if comment.file_path == context.file_path
      and comment.line_side == context.line_side
      and (not in_range or mismatched)
      and comment.status ~= "unresolved" then
      unresolved[#unresolved + 1] = comment.id
      comment.status = "unresolved"
      comment.updated_at = timestamp()
    end
  end
  if #unresolved == 0 and hydrated == 0 then
    return false
  end

  mark_dirty(diff_id)
  for _, comment_id in ipairs(unresolved) do
    for _, thread in ipairs(dstate.threads) do
      remove_from_thread(thread, comment_id)
      maybe_drop_thread(dstate, thread)
    end
  end
  if #unresolved > 0 then
    Util.warn(("Marked %d comment(s) unresolved after diff changes"):format(#unresolved))
  end
  return true
end

---@param comments commentry.DraftComment[]
---@param prompt string
---@param cb fun(comment: commentry.DraftComment)
local function select_comment(comments, prompt, cb)
  if #comments == 0 then
    return
  end
  if #comments == 1 then
    cb(comments[1])
    return
  end
  vim.ui.select(comments, {
    prompt = prompt,
    format_item = function(item)
      local preview = item.body:gsub("\n", " ")
      if #preview > 60 then
        preview = preview:sub(1, 57) .. "..."
      end
      return ("[%s] %s"):format(item.comment_type or "note", preview)
    end,
  }, function(choice)
    if choice then
      cb(choice)
    end
  end)
end

---@param context table
local function render_for_context(context)
  local diff_id = require_context_id(context.view, "Unable to resolve review context")
  if not diff_id then
    return
  end
  local reconciled = reconcile_for_context(diff_id, context)
  local dstate = diff_state(diff_id)
  local comments = {}
  for _, comment in ipairs(dstate.comments) do
    if comment.file_path == context.file_path
      and comment.line_side == context.line_side
      and comment.status ~= "unresolved" then
      comments[#comments + 1] = comment
    end
  end
  Diffview.render_comment_markers(context.bufnr, comments)
  if type(Diffview.render_file_review_indicator) == "function" then
    local reviewed = dstate.file_reviews[context.file_path] == true
    Diffview.render_file_review_indicator(context.bufnr, reviewed)
  end
  if reconciled then
    persist_for_view(diff_id, context.view, "Failed to persist reconciled comments")
  end
end

---@param context table
---@return commentry.DraftComment[]
local function active_comments_for_line(context)
  local diff_id = require_context_id(context.view, "Unable to resolve review context")
  if not diff_id then
    return {}
  end
  local dstate = diff_state(diff_id)
  local comments = {}
  for _, comment in ipairs(dstate.comments) do
    if comment.file_path == context.file_path
      and comment.line_side == context.line_side
      and contains_line(comment, context.line_number)
      and comment.status ~= "unresolved" then
      comments[#comments + 1] = comment
    end
  end
  return comments
end

---@param diff_id string
---@param context table
---@return commentry.DraftComment[]
local function jumpable_comments_for_context(diff_id, context)
  local dstate = diff_state(diff_id)
  local comments = {}
  for _, comment in ipairs(dstate.comments) do
    if comment.status ~= "unresolved"
      and comment.file_path == context.file_path
      and comment.line_side == context.line_side then
      comments[#comments + 1] = comment
    end
  end
  table.sort(comments, function(a, b)
    if a.file_path ~= b.file_path then
      return a.file_path < b.file_path
    end
    if a.line_side ~= b.line_side then
      return a.line_side < b.line_side
    end
    local a_start = line_start_for(a) or 1
    local b_start = line_start_for(b) or 1
    if a_start ~= b_start then
      return a_start < b_start
    end
    local a_end = a.line_end or a_start
    local b_end = b.line_end or b_start
    if a_end ~= b_end then
      return a_end < b_end
    end
    if (a.created_at or "") ~= (b.created_at or "") then
      return (a.created_at or "") < (b.created_at or "")
    end
    return (a.id or "") < (b.id or "")
  end)
  return comments
end

---@param comment commentry.DraftComment
---@return string
local function comment_location_label(comment)
  local side = comment.line_side or "head"
  local line_start = comment.line_start or comment.line_number
  local line_end = comment.line_end or line_start
  if not is_integer(line_start) then
    return ("%s:file"):format(side)
  end
  if not is_integer(line_end) then
    line_end = line_start
  end
  if line_end <= line_start then
    return ("%s:L%d"):format(side, line_start)
  end
  return ("%s:L%d-L%d"):format(side, line_start, line_end)
end

---@param comment commentry.DraftComment
---@return string
local function list_entry_label(comment)
  local preview = comment.body:gsub("\n", " ")
  if #preview > 72 then
    preview = preview:sub(1, 69) .. "..."
  end
  local comment_type = comment.comment_type or "note"
  return ("%s @ %s [%s] %s"):format(comment.file_path, comment_location_label(comment), comment_type, preview)
end

---@param comment commentry.DraftComment
---@return boolean
local function jump_to_comment(comment)
  local context, err = current_context()
  if not context then
    Util.error(err or "No diffview context")
    return false
  end
  if comment.file_path ~= context.file_path or comment.line_side ~= context.line_side then
    Util.info("Select the target diff file/side before jumping to this comment")
    return false
  end
  local line = math.max(comment.line_number, 1)
  line = math.max(line_start_for(comment) or line, 1)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  return true
end

---@return boolean, string|nil
local function snacks_picker_available()
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    return false, "snacks.nvim is required for :Commentry list-comments"
  end
  local picker = snacks and snacks.picker or nil
  if type(picker) ~= "table" or type(picker.select) ~= "function" then
    return false, "snacks.nvim picker.select is required for :Commentry list-comments"
  end
  return true, nil
end

---@return table|nil, string|nil
current_context = function()
  local context, err = Diffview.current_file_context()
  if not context then
    return nil, err
  end
  return context, nil
end

---@param file_path string
---@param line_start integer
---@param line_end integer
---@param line_side string
---@return boolean, string|nil
local function validate_anchor(file_path, line_start, line_end, line_side)
  if type(file_path) ~= "string" or file_path == "" then
    return false, "file_path is required"
  end
  if not is_integer(line_start) then
    return false, "line_start must be a positive integer"
  end
  if not is_integer(line_end) then
    return false, "line_end must be a positive integer"
  end
  if line_end < line_start then
    return false, "line_end must be >= line_start"
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
---@field line_start integer
---@field line_end integer
---@field line_side '"base"'|'"head"'

---@param file_path string
---@param line_start integer
---@param line_side '"base"'|'"head"'
---@param line_end? integer
---@return commentry.Anchor|nil, string|nil
function M.build_anchor(file_path, line_start, line_side, line_end)
  line_end = line_end or line_start
  local ok, err = validate_anchor(file_path, line_start, line_end, line_side)
  if not ok then
    return nil, err
  end
  return {
    file_path = file_path,
    line_number = line_start,
    line_start = line_start,
    line_end = line_end,
    line_side = line_side,
  }, nil
end

---@param anchor commentry.Anchor
---@return string|nil, string|nil
function M.anchor_key(anchor)
  if type(anchor) ~= "table" then
    return nil, "anchor is required"
  end
  local line_start = anchor.line_start or anchor.line_number
  local line_end = anchor.line_end or line_start
  local ok, err = validate_anchor(anchor.file_path, line_start, line_end, anchor.line_side)
  if not ok then
    return nil, err
  end
  return ("%s|%s|%d-%d"):format(anchor.file_path, anchor.line_side, line_start, line_end), nil
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
---@field line_start integer
---@field line_end integer
---@field line_side '"base"'|'"head"'
---@field comment_type string
---@field body string
---@field created_at string
---@field updated_at string
---@field status? string

---@class commentry.CommentInput
---@field id? string
---@field created_at? string
---@field updated_at? string
---@field status? string
---@field comment_type? string

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
  local line_start = anchor.line_start or anchor.line_number
  local line_end = anchor.line_end or line_start
  local ok, err = validate_anchor(anchor.file_path, line_start, line_end, anchor.line_side)
  if not ok then
    return nil, err
  end
  local comment_type = opts.comment_type or default_comment_type()
  if not is_valid_comment_type(comment_type) then
    return nil, ("comment_type must be one of: %s"):format(table.concat(comment_type_choices(), ", "))
  end
  local created_at = opts.created_at or timestamp()
  local updated_at = opts.updated_at or created_at
  return {
    id = opts.id or M.new_id("c"),
    diff_id = diff_id,
    file_path = anchor.file_path,
    line_number = line_start,
    line_start = line_start,
    line_end = line_end,
    line_side = anchor.line_side,
    comment_type = comment_type,
    body = body,
    created_at = created_at,
    updated_at = updated_at,
    status = opts.status,
  },
    nil
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
  if not is_valid_comment_type(comment.comment_type) then
    return nil, ("comment_type must be one of: %s"):format(table.concat(comment_type_choices(), ", "))
  end
  local updated = vim.deepcopy(comment)
  updated.body = body
  updated.updated_at = timestamp()
  return updated, nil
end

---@param comment commentry.DraftComment
---@param comment_type string
---@return commentry.DraftComment|nil, string|nil
function M.update_type(comment, comment_type)
  if type(comment) ~= "table" then
    return nil, "comment is required"
  end
  if not is_valid_comment_type(comment_type) then
    return nil, ("comment_type must be one of: %s"):format(table.concat(comment_type_choices(), ", "))
  end
  local updated = vim.deepcopy(comment)
  updated.comment_type = comment_type
  updated.updated_at = timestamp()
  return updated, nil
end

---@class commentry.CommentThread
---@field id string
---@field diff_id string
---@field file_path string
---@field line_number integer
---@field line_start integer
---@field line_end integer
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
  local line_start = anchor.line_start or anchor.line_number
  local line_end = anchor.line_end or line_start
  local ok, err = validate_anchor(anchor.file_path, line_start, line_end, anchor.line_side)
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
    line_number = line_start,
    line_start = line_start,
    line_end = line_end,
    line_side = anchor.line_side,
    comment_ids = comment_ids or {},
  },
    nil
end

function M.render_current_buffer()
  local context, err = current_context()
  if not context then
    Util.warn(err or "No diffview context")
    return
  end
  render_for_context(context)
end

---@return boolean
function M.refresh_hover_preview()
  local context, err = current_context()
  if not context then
    Diffview.clear_hover_preview(vim.api.nvim_get_current_buf())
    if err then
      Util.debug("hover preview skipped", err)
    end
    return false
  end
  local comments = active_comments_for_line(context)
  if #comments == 0 then
    Diffview.clear_hover_preview(context.bufnr)
    return false
  end
  Diffview.render_hover_preview(context.bufnr, context.line_number, comments)
  return true
end

function M.list_comments()
  local context, context_err = current_context()
  if not context then
    Util.error(context_err or "No diffview context")
    return
  end

  local snacks_ok, snacks_err = snacks_picker_available()
  if not snacks_ok then
    Util.error(snacks_err)
    return
  end

  local diff_id = require_context_id(context.view, "Unable to resolve review context")
  if not diff_id then
    return
  end
  local comments = jumpable_comments_for_context(diff_id, context)
  if #comments == 0 then
    Util.info("No jumpable draft comments for current diff file/side")
    return
  end

  local snacks = require("snacks")
  snacks.picker.select(comments, {
    prompt = "Commentry draft comments",
    format_item = list_entry_label,
  }, function(choice)
    if not choice then
      return
    end
    jump_to_comment(choice)
    M.refresh_hover_preview()
  end)
end

---@param diff_id string
---@param current_path string
---@return string[]
local function ordered_review_files(diff_id, current_path)
  local files = {}
  local seen = {}

  local function push(path)
    if type(path) ~= "string" or path == "" or seen[path] then
      return
    end
    seen[path] = true
    files[#files + 1] = path
  end

  local view = nil
  local context, _ = current_context()
  if type(context) == "table" then
    view = context.view
  end

  if type(Diffview.list_view_files) == "function" and type(view) == "table" then
    for _, path in ipairs(Diffview.list_view_files(view)) do
      push(path)
    end
  end

  if #files == 0 then
    local dstate = diff_state(diff_id)
    for _, comment in ipairs(dstate.comments) do
      push(comment.file_path)
    end
    for path in pairs(dstate.file_reviews or {}) do
      push(path)
    end
    table.sort(files)
  end

  push(current_path)
  return files
end

---@return boolean|nil, string|nil
function M.current_file_reviewed()
  local context, err = current_context()
  if not context then
    return nil, err or "No diffview context"
  end
  local diff_id = M.context_id_for_view(context.view)
  if not diff_id then
    return nil, "context_id_unavailable"
  end
  return diff_state(diff_id).file_reviews[context.file_path] == true, nil
end

function M.toggle_file_reviewed()
  local context, err = current_context()
  if not context then
    Util.error(err or "No diffview context")
    return
  end
  local diff_id = require_context_id(context.view, "Unable to resolve review context")
  if not diff_id then
    return
  end

  local dstate = diff_state(diff_id)
  local reviewed = dstate.file_reviews[context.file_path] == true
  dstate.file_reviews[context.file_path] = not reviewed

  mark_dirty(diff_id)
  render_for_context(context)
  persist_for_view(diff_id, context.view, "Failed to persist file review state")
  if dstate.file_reviews[context.file_path] then
    Util.info(("Marked `%s` reviewed"):format(context.file_path))
  else
    Util.info(("Marked `%s` unreviewed"):format(context.file_path))
  end
end

function M.next_unreviewed_file()
  local context, err = current_context()
  if not context then
    Util.error(err or "No diffview context")
    return
  end
  local diff_id = require_context_id(context.view, "Unable to resolve review context")
  if not diff_id then
    return
  end

  local dstate = diff_state(diff_id)
  local files = ordered_review_files(diff_id, context.file_path)
  if #files == 0 then
    Util.info("No files available for review navigation")
    return
  end

  local start_index = 1
  for index, path in ipairs(files) do
    if path == context.file_path then
      start_index = index
      break
    end
  end

  local next_path = nil
  for offset = 1, #files - 1 do
    local idx = ((start_index + offset - 1) % #files) + 1
    local path = files[idx]
    if dstate.file_reviews[path] ~= true then
      next_path = path
      break
    end
  end

  if not next_path then
    Util.info("No other unreviewed files")
    return
  end

  if type(Diffview.focus_file) == "function" then
    local ok, focus_err = Diffview.focus_file(context.view, next_path)
    if not ok then
      Util.warn(focus_err or "Unable to focus target file in diffview")
      return
    end
  else
    Util.warn("Diffview navigation helpers are unavailable")
    return
  end

  Util.info(("Jumped to next unreviewed file: %s"):format(next_path))
end

---@param diff_id string
---@return commentry.DraftComment[]
local function exportable_comments(diff_id)
  local dstate = diff_state(diff_id)
  local comments = {}
  for _, comment in ipairs(dstate.comments) do
    if comment.status ~= "unresolved" then
      comments[#comments + 1] = comment
    end
  end
  table.sort(comments, function(a, b)
    if a.file_path ~= b.file_path then
      return a.file_path < b.file_path
    end
    if a.line_side ~= b.line_side then
      return a.line_side < b.line_side
    end
    local a_start = a.line_start or a.line_number or 1
    local b_start = b.line_start or b.line_number or 1
    if a_start ~= b_start then
      return a_start < b_start
    end
    local a_end = a.line_end or a_start
    local b_end = b.line_end or b_start
    if a_end ~= b_end then
      return a_end < b_end
    end
    if (a.created_at or "") ~= (b.created_at or "") then
      return (a.created_at or "") < (b.created_at or "")
    end
    return (a.id or "") < (b.id or "")
  end)
  return comments
end

---@param diff_id string
---@return commentry.DraftComment[]
function M.exportable_comments(diff_id)
  return vim.deepcopy(exportable_comments(diff_id))
end

---@param context? table
---@return string|nil, string|nil
function M.generate_export_markdown(context)
  local resolved_context = context
  local context_err = nil
  if not resolved_context then
    resolved_context, context_err = current_context()
  end
  if type(resolved_context) ~= "table" then
    return nil, context_err or "No diffview context"
  end

  local view = resolved_context.view or resolved_context
  local diff_id, diff_err = M.context_id_for_view(view)
  if not diff_id then
    return nil, diff_err or "Unable to resolve review context"
  end
  local comments = exportable_comments(diff_id)

  local lines = {
    "# Commentry Draft Export",
    "",
    ("- Context: `%s`"):format(diff_id),
    ("- Comments: %d"):format(#comments),
    "",
  }

  if #comments == 0 then
    lines[#lines + 1] = "_No draft comments._"
    return table.concat(lines, "\n"), nil
  end

  local current_file = nil
  for _, comment in ipairs(comments) do
    if comment.file_path ~= current_file then
      if current_file then
        lines[#lines + 1] = ""
      end
      current_file = comment.file_path
      lines[#lines + 1] = ("## `%s`"):format(current_file)
      lines[#lines + 1] = ""
    end

    local comment_type = comment.comment_type or "note"
    lines[#lines + 1] = ("- [%s] `%s`"):format(comment_type, comment_location_label(comment))

    local body_lines = vim.split(comment.body or "", "\n", { plain = true })
    if #body_lines == 0 then
      body_lines = { "" }
    end
    for _, body_line in ipairs(body_lines) do
      lines[#lines + 1] = ("  %s"):format(body_line)
    end
    lines[#lines + 1] = ""
  end

  return table.concat(lines, "\n"), nil
end

---@param cmd_args string?
---@return string|nil, string|nil
local function export_register_from_args(cmd_args)
  if type(cmd_args) ~= "string" then
    return nil, nil
  end
  local args = vim.trim(cmd_args)
  if args == "" then
    return nil, nil
  end
  if args == "stdout" then
    return nil, nil
  end
  if args == "register" then
    return '"', nil
  end
  local prefix = "register:"
  if args:sub(1, #prefix) == prefix then
    local register = args:sub(#prefix + 1)
    if #register == 1 then
      return register, nil
    end
    return nil, "Register destination must be a single register name (example: register:a)"
  end
  return nil, "Unknown export destination. Use `stdout`, `register`, or `register:<name>`"
end

---@param cmd_args string?
function M.export_comments(cmd_args)
  local register, parse_err = export_register_from_args(cmd_args)
  if parse_err then
    Util.error(parse_err)
    return
  end

  local markdown, export_err = M.generate_export_markdown()
  if not markdown then
    Util.error(export_err or "Failed to generate comment export")
    return
  end

  if not register then
    print(markdown)
    return
  end

  vim.fn.setreg(register, markdown)
  Util.info(("Exported draft comments to register `%s`"):format(register))
end

---@param view table
---@return boolean
function M.load_for_view(view)
  local diff_id = require_context_id(view, "Unable to resolve review context")
  if not diff_id then
    return false
  end
  if is_dirty(diff_id) then
    Util.warn("Skipping store reload: unsaved in-memory comments exist")
    return false
  end
  local root = project_root_for_view(view)
  if not root then
    Util.warn("Unable to resolve project root for comment store")
    return false
  end
  local path, path_err = path_for_context(root, diff_id)
  if not path then
    Util.warn(path_err or "Failed to resolve comment store path")
    return false
  end
  local store, read_err = Store.read(path)
  if read_err == "not_found" then
    return false
  end
  if read_err then
    Util.warn(read_err)
    return false
  end
  apply_store(diff_id, store)
  return true
end

---@return boolean
function M.load_current_view()
  local view, err = Diffview.get_current_view()
  if not view then
    Util.warn(err or "No diffview view found")
    return false
  end
  return M.load_for_view(view)
end

---@return table|nil, string|nil
function M.debug_store_context()
  local view, view_err = Diffview.get_current_view()
  if not view then
    return nil, view_err or "No diffview view found"
  end

  local context_id, context_err = M.context_id_for_view(view)
  if not context_id then
    return nil, context_err or "context_id_unavailable"
  end

  local root = project_root_for_view(view)
  if not root then
    return nil, "project_root_unavailable"
  end

  local path, path_err = path_for_context(root, context_id)
  if not path then
    return nil, path_err or "store_path_failed"
  end

  local stat = uv.fs_stat(path)
  local context = nil
  if type(Diffview.review_context_for_view) == "function" then
    context = Diffview.review_context_for_view(view)
  end

  return {
    context_id = context_id,
    mode = context and context.mode or nil,
    revisions = context and context.revisions or nil,
    project_root = root,
    store_path = path,
    store_exists = stat ~= nil,
  },
    nil
end

---@param diff_id string
---@param prompt string
---@param initial_type? string
---@param cb fun(comment_type: string)
local function select_comment_type(diff_id, prompt, initial_type, cb)
  local choices = comment_type_choices()
  local selected = initial_type
  if not is_valid_comment_type(selected) then
    selected = selected_comment_type(diff_id)
  end
  table.sort(choices, function(a, b)
    if a == selected then
      return true
    end
    if b == selected then
      return false
    end
    return a < b
  end)

  vim.ui.select(choices, {
    prompt = prompt,
    format_item = function(item)
      if item == selected then
        return item .. " (default)"
      end
      return item
    end,
  }, function(choice)
    if type(choice) == "string" and choice ~= "" then
      cb(choice)
    end
  end)
end

---@param context table
---@return integer, integer
local function visual_line_range(context)
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = tonumber(start_pos[2]) or 0
  local end_line = tonumber(end_pos[2]) or 0
  if start_line < 1 or end_line < 1 then
    local line = context.line_number
    return line, line
  end
  local start_buf = tonumber(start_pos[1]) or 0
  local end_buf = tonumber(end_pos[1]) or 0
  if (start_buf > 0 and start_buf ~= context.bufnr) or (end_buf > 0 and end_buf ~= context.bufnr) then
    local line = context.line_number
    return line, line
  end
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  return start_line, end_line
end

function M.add_comment()
  local context, err = current_context()
  if not context then
    Util.error(err or "No diffview context")
    return
  end
  local anchor, anchor_err = anchor_from_context(context)
  if not anchor then
    Util.error(anchor_err or "Invalid line anchor")
    return
  end
  local diff_id = require_context_id(context.view, "Unable to resolve review context")
  if not diff_id then
    return
  end
  local active_type = selected_comment_type(diff_id)
  vim.ui.input({ prompt = ("Add %s comment: "):format(active_type) }, function(input)
    if not input or input == "" then
      return
    end
    local comment, comment_err = M.new_comment(diff_id, anchor, input, { comment_type = active_type })
    if not comment then
      Util.error(comment_err or "Failed to create comment")
      return
    end
    comment.line_content = line_text_at(context.bufnr, context.line_number)
    local dstate = diff_state(diff_id)
    upsert_comment(dstate, comment)
    local thread, thread_err = ensure_thread(diff_id, anchor)
    if not thread then
      Util.error(thread_err or "Failed to create thread")
      return
    end
    thread.comment_ids[#thread.comment_ids + 1] = comment.id
    mark_dirty(diff_id)
    render_for_context(context)
    persist_for_view(diff_id, context.view, "Failed to persist comment")
  end)
end

function M.add_range_comment()
  local context, err = current_context()
  if not context then
    Util.error(err or "No diffview context")
    return
  end

  local line_start, line_end = visual_line_range(context)
  local anchor, anchor_err = M.build_anchor(context.file_path, line_start, context.line_side, line_end)
  if not anchor then
    Util.error(anchor_err or "Invalid range anchor")
    return
  end

  local diff_id = require_context_id(context.view, "Unable to resolve review context")
  if not diff_id then
    return
  end
  local active_type = selected_comment_type(diff_id)
  local prompt = ("Add %s range comment (%d-%d): "):format(active_type, line_start, line_end)

  vim.ui.input({ prompt = prompt }, function(input)
    if not input or input == "" then
      return
    end
    local comment, comment_err = M.new_comment(diff_id, anchor, input, { comment_type = active_type })
    if not comment then
      Util.error(comment_err or "Failed to create range comment")
      return
    end
    comment.line_content = line_text_at(context.bufnr, line_start)
    local dstate = diff_state(diff_id)
    upsert_comment(dstate, comment)
    local thread, thread_err = ensure_thread(diff_id, anchor)
    if not thread then
      Util.error(thread_err or "Failed to create thread")
      return
    end
    thread.comment_ids[#thread.comment_ids + 1] = comment.id
    mark_dirty(diff_id)
    render_for_context(context)
    persist_for_view(diff_id, context.view, "Failed to persist range comment")
  end)
end

function M.edit_comment()
  local context, err = current_context()
  if not context then
    Util.error(err or "No diffview context")
    return
  end
  local diff_id = require_context_id(context.view, "Unable to resolve review context")
  if not diff_id then
    return
  end
  local dstate = diff_state(diff_id)
  local comments = active_comments_for_line(context)
  if #comments == 0 then
    Util.info("No draft comments for this line")
    return
  end
  select_comment(comments, "Edit comment", function(target)
    vim.ui.input({ prompt = "Edit comment: ", default = target.body }, function(input)
      if not input or input == "" then
        return
      end
      local updated, update_err = M.update_body(target, input)
      if not updated then
        Util.error(update_err or "Failed to update comment")
        return
      end
      updated.status = nil
      upsert_comment(dstate, updated)
      mark_dirty(diff_id)
      render_for_context(context)
      persist_for_view(diff_id, context.view, "Failed to persist comment")
    end)
  end)
end

function M.delete_comment()
  local context, err = current_context()
  if not context then
    Util.error(err or "No diffview context")
    return
  end
  local diff_id = require_context_id(context.view, "Unable to resolve review context")
  if not diff_id then
    return
  end
  local dstate = diff_state(diff_id)
  local comments = active_comments_for_line(context)
  if #comments == 0 then
    Util.info("No draft comments for this line")
    return
  end
  select_comment(comments, "Delete comment", function(target)
    remove_comment(dstate, target.id)
    remove_comment_from_threads(dstate, target.id)
    mark_dirty(diff_id)
    render_for_context(context)
    persist_for_view(diff_id, context.view, "Failed to persist comment")
  end)
end

function M.set_comment_type()
  local context, err = current_context()
  if not context then
    Util.error(err or "No diffview context")
    return
  end

  local diff_id = require_context_id(context.view, "Unable to resolve review context")
  if not diff_id then
    return
  end
  local dstate = diff_state(diff_id)
  local comments = active_comments_for_line(context)

  if #comments == 0 then
    select_comment_type(diff_id, "Default comment type", selected_comment_type(diff_id), function(choice)
      dstate.selected_comment_type = choice
      Util.info(("Default comment type set to %s"):format(choice))
    end)
    return
  end

  select_comment(comments, "Set comment type", function(target)
    select_comment_type(diff_id, "Set comment type", target.comment_type, function(choice)
      local updated, update_err = M.update_type(target, choice)
      if not updated then
        Util.error(update_err or "Failed to update comment type")
        return
      end
      updated.status = nil
      dstate.selected_comment_type = choice
      upsert_comment(dstate, updated)
      mark_dirty(diff_id)
      render_for_context(context)
      persist_for_view(diff_id, context.view, "Failed to persist comment")
    end)
  end)
end

return M
