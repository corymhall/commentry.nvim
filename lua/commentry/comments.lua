local Diffview = require("commentry.diffview")
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

---@param diff_id string
---@return table
local function diff_state(diff_id)
  if not state.diffs[diff_id] then
    state.diffs[diff_id] = {
      comments = {},
      threads = {},
      comments_by_id = {},
      threads_by_id = {},
      dirty = false,
    }
  end
  return state.diffs[diff_id]
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

---@param context table
---@return commentry.Anchor|nil, string|nil
local function anchor_from_context(context)
  if type(context) ~= "table" then
    return nil, "diffview context is required"
  end
  return M.build_anchor(context.file_path, context.line_number, context.line_side)
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

---@param diff_id string
---@param anchor commentry.Anchor
---@return commentry.CommentThread|nil, string|nil
local function find_thread(diff_id, anchor)
  local thread_id, err = M.thread_id(diff_id, anchor)
  if not thread_id then
    return nil, err
  end
  local dstate = diff_state(diff_id)
  return dstate.threads_by_id[thread_id], nil
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
---@param thread commentry.CommentThread
---@return commentry.DraftComment[]
local function comments_for_thread(dstate, thread)
  local results = {}
  for _, comment_id in ipairs(thread.comment_ids) do
    local comment = dstate.comments_by_id[comment_id]
    if comment then
      results[#results + 1] = comment
    end
  end
  return results
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
  dstate.comments_by_id = {}
  dstate.threads_by_id = {}

  if type(store.comments) == "table" then
    for _, comment in ipairs(store.comments) do
      if type(comment) == "table" then
        upsert_comment(dstate, comment)
      end
    end
  end

  if type(store.threads) == "table" then
    for _, thread in ipairs(store.threads) do
      if type(thread) == "table" and type(thread.id) == "string" then
        dstate.threads_by_id[thread.id] = thread
        dstate.threads[#dstate.threads + 1] = thread
      end
    end
  end
end

---@param diff_id string
---@param project_root string
---@return boolean, string|string[]|nil
local function save_store(diff_id, project_root)
  local path, path_err = Store.path_for_project(project_root)
  if not path then
    return false, path_err or "store_path_failed"
  end

  local dstate = diff_state(diff_id)
  local store = {
    project_root = project_root,
    diff_id = diff_id,
    comments = vim.deepcopy(dstate.comments),
    threads = vim.deepcopy(dstate.threads),
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
  local ok, save_err = save_store(diff_id, root)
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
    local in_range = comment.line_number >= 1 and comment.line_number <= line_count
    local missing_line_content = in_target and in_range and (type(comment.line_content) ~= "string" or comment.line_content == "")
    local mismatched = false
    if missing_line_content then
      local current = line_text_at(context.bufnr, comment.line_number)
      if type(current) == "string" then
        comment.line_content = current
        hydrated = hydrated + 1
      end
    elseif in_target and in_range then
      local current = line_text_at(context.bufnr, comment.line_number)
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
      return preview
    end,
  }, function(choice)
    if choice then
      cb(choice)
    end
  end)
end

---@param context table
local function render_for_context(context)
  local diff_id = diff_id_for_view(context.view)
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
  if reconciled then
    persist_for_view(diff_id, context.view, "Failed to persist reconciled comments")
  end
end

---@param context table
---@return commentry.DraftComment[]
local function active_comments_for_line(context)
  local diff_id = diff_id_for_view(context.view)
  local dstate = diff_state(diff_id)
  local comments = {}
  for _, comment in ipairs(dstate.comments) do
    if comment.file_path == context.file_path
      and comment.line_side == context.line_side
      and comment.line_number == context.line_number
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
    if a.line_number ~= b.line_number then
      return a.line_number < b.line_number
    end
    return (a.created_at or "") < (b.created_at or "")
  end)
  return comments
end

---@param comment commentry.DraftComment
---@return string
local function list_entry_label(comment)
  local preview = comment.body:gsub("\n", " ")
  if #preview > 72 then
    preview = preview:sub(1, 69) .. "..."
  end
  return ("%s:%d [%s] %s"):format(comment.file_path, comment.line_number, comment.line_side, preview)
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

  local diff_id = diff_id_for_view(context.view)
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

---@param view table
---@return boolean
function M.load_for_view(view)
  local diff_id = diff_id_for_view(view)
  if is_dirty(diff_id) then
    Util.warn("Skipping store reload: unsaved in-memory comments exist")
    return false
  end
  local root = project_root_for_view(view)
  if not root then
    Util.warn("Unable to resolve project root for comment store")
    return false
  end
  local path, path_err = Store.path_for_project(root)
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
  vim.ui.input({ prompt = "Add comment: " }, function(input)
    if not input or input == "" then
      return
    end
    local diff_id = diff_id_for_view(context.view)
    local comment, comment_err = M.new_comment(diff_id, anchor, input)
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

function M.edit_comment()
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
  local diff_id = diff_id_for_view(context.view)
  local dstate = diff_state(diff_id)
  local thread, thread_err = find_thread(diff_id, anchor)
  if not thread then
    if thread_err then
      Util.error(thread_err)
    else
      Util.info("No draft comments for this line")
    end
    return
  end
  local comments = comments_for_thread(dstate, thread)
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
  local anchor, anchor_err = anchor_from_context(context)
  if not anchor then
    Util.error(anchor_err or "Invalid line anchor")
    return
  end
  local diff_id = diff_id_for_view(context.view)
  local dstate = diff_state(diff_id)
  local thread, thread_err = find_thread(diff_id, anchor)
  if not thread then
    if thread_err then
      Util.error(thread_err)
    else
      Util.info("No draft comments for this line")
    end
    return
  end
  local comments = comments_for_thread(dstate, thread)
  if #comments == 0 then
    Util.info("No draft comments for this line")
    return
  end
  select_comment(comments, "Delete comment", function(target)
    remove_comment(dstate, target.id)
    remove_from_thread(thread, target.id)
    maybe_drop_thread(dstate, thread)
    mark_dirty(diff_id)
    render_for_context(context)
    persist_for_view(diff_id, context.view, "Failed to persist comment")
  end)
end

return M
