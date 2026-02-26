local M = {}

local Config = require("commentry.config")
local hover_ns = vim.api.nvim_create_namespace("commentry-hover-preview")
local file_review_ns = vim.api.nvim_create_namespace("commentry-file-review")
local hover_attached = {}
local uv = vim.uv or vim.loop
local ROOT_CANDIDATE_KEYS = { "git_root", "toplevel", "root", "cwd", "path" }
local view_context_by_tabpage = {}

--- mark buffer.
local function mark_buffer(bufnr)
  if type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_set_var, bufnr, "commentry_diffview", true)
  end
end

---@return string|nil
local function git_root()
  local output = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 then
    return nil
  end
  local root = output[1]
  if type(root) ~= "string" or root == "" then
    return nil
  end
  return root
end

---@param root string
---@return boolean|nil, string|nil
local function has_local_changes(root)
  local output = vim.fn.systemlist({ "git", "-C", root, "status", "--porcelain" })
  if vim.v.shell_error ~= 0 then
    return nil, "git_status_failed"
  end
  return #output > 0, nil
end

---@param args? string[]|string
---@return boolean
local function is_empty_args(args)
  if args == nil then
    return true
  end
  if type(args) == "string" then
    return args == ""
  end
  if type(args) == "table" then
    return #args == 0
  end
  return true
end

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

---@param args? string[]|string
---@return string[]
local function normalize_args(args)
  if type(args) == "string" then
    if args == "" then
      return {}
    end
    return { args }
  end
  if type(args) ~= "table" then
    return {}
  end
  local normalized = {}
  for _, token in ipairs(args) do
    if type(token) == "string" and token ~= "" then
      normalized[#normalized + 1] = token
    end
  end
  return normalized
end

---@param token string
---@return boolean
local function token_looks_like_path(token)
  if token:match("^%.?%./") or token:match("^/") then
    return true
  end
  local stat = uv.fs_stat(token)
  return stat ~= nil
end

---@param token string
---@return boolean
local function token_looks_like_revision(token)
  if token == "" or token:sub(1, 1) == "-" or token:sub(1, 1) == ":" then
    return false
  end
  if token:find("...", 1, true) or token:find("..", 1, true) then
    return true
  end
  if token == "HEAD" or token:match("^HEAD[%^~%-%w_%.]*$") then
    return true
  end
  if token_looks_like_path(token) then
    return false
  end
  if token:match("^[%x]+$") and #token >= 7 then
    return true
  end
  return token:match("^[%w][%w%._%-/]*$") ~= nil
end

---@param args? string[]|string
---@return string[]|nil
local function revisions_from_args(args)
  local tokens = normalize_args(args)
  if #tokens == 0 then
    return nil
  end
  local revisions = {}
  for _, token in ipairs(tokens) do
    if token_looks_like_revision(token) then
      revisions[#revisions + 1] = token
      if token:find("...", 1, true) or token:find("..", 1, true) then
        break
      end
    end
  end
  if #revisions == 0 then
    return nil
  end
  return revisions
end

---@param value any
---@return string|nil
local function ref_from_value(value)
  if type(value) == "string" and value ~= "" then
    return value
  end
  if type(value) ~= "table" then
    return nil
  end
  if type(value.commit) == "table" then
    return value.commit.hash or value.commit.oid or value.commit.rev or value.commit.name
  end
  return value.hash or value.oid or value.rev or value.name
end

---@param view table
---@return string[]|nil
local function revisions_from_view(view)
  local explicit = view.rev_arg or view.rev_args or view.range or view.range_arg
  local revisions = revisions_from_args(explicit)
  if revisions then
    return revisions
  end
  local left = ref_from_value(view.left)
  local right = ref_from_value(view.right)
  if left and right then
    return { ("%s..%s"):format(left, right) }
  end
  return nil
end

---@param root string
---@param ref string
---@return string|nil
local function resolve_commit_ref(root, ref)
  if type(root) ~= "string" or root == "" or type(ref) ~= "string" or ref == "" then
    return nil
  end
  local output = vim.fn.systemlist({ "git", "-C", root, "rev-parse", "--verify", ("%s^{commit}"):format(ref) })
  if vim.v.shell_error ~= 0 then
    return nil
  end
  local oid = output[1]
  if type(oid) == "string" and oid:match("^[0-9a-fA-F]+$") then
    return oid:lower()
  end
  return nil
end

---@param token string
---@return string|nil, string|nil, string|nil
local function split_revision_range(token)
  if type(token) ~= "string" or token == "" then
    return nil, nil, nil
  end

  local triple_start = token:find("...", 1, true)
  if triple_start then
    local left = token:sub(1, triple_start - 1)
    local right = token:sub(triple_start + 3)
    if left ~= "" and right ~= "" then
      return left, right, "..."
    end
  end

  local double_start = token:find("..", 1, true)
  if double_start then
    local left = token:sub(1, double_start - 1)
    local right = token:sub(double_start + 2)
    if left ~= "" and right ~= "" then
      return left, right, ".."
    end
  end

  return nil, nil, nil
end

---@param root string
---@param revisions string[]|nil
---@return table[]|nil
local function resolve_revision_anchors(root, revisions)
  if type(revisions) ~= "table" or #revisions == 0 then
    return nil
  end

  local anchors = {}
  for _, token in ipairs(revisions) do
    if type(token) == "string" and token ~= "" then
      local left_ref, right_ref, separator = split_revision_range(token)
      if separator then
        local left_sha = resolve_commit_ref(root, left_ref)
        local right_sha = resolve_commit_ref(root, right_ref)
        if left_sha and right_sha then
          anchors[#anchors + 1] = {
            token = token,
            separator = separator,
            from = left_sha,
            to = right_sha,
            canonical = ("%s%s%s"):format(left_sha, separator, right_sha),
          }
        end
      else
        local commit = resolve_commit_ref(root, token)
        if commit then
          anchors[#anchors + 1] = {
            token = token,
            commit = commit,
          }
        end
      end
    end
  end

  if #anchors == 0 then
    return nil
  end
  return anchors
end

---@param view? table
---@return integer|nil
local function tabpage_id_for_view(view)
  if type(view) ~= "table" then
    return nil
  end
  local id = view.tabpage or view.tabnr or view.id or view.view_id
  if type(id) == "number" and id > 0 then
    return id
  end
  return nil
end

---@param view? table
---@return table|nil
function M.review_context_for_view(view)
  if type(view) ~= "table" then
    return nil
  end
  if type(view.commentry_review_context) == "table" then
    return vim.deepcopy(view.commentry_review_context)
  end
  local tabpage = tabpage_id_for_view(view)
  if tabpage and type(view_context_by_tabpage[tabpage]) == "table" then
    return vim.deepcopy(view_context_by_tabpage[tabpage])
  end
  return nil
end

---@param view? table
---@param context table
function M.set_review_context_for_view(view, context)
  if type(view) ~= "table" or type(context) ~= "table" then
    return
  end
  view.commentry_review_context = vim.deepcopy(context)
  local tabpage = tabpage_id_for_view(view)
  if tabpage then
    view_context_by_tabpage[tabpage] = vim.deepcopy(context)
  end
end

---@param args? string[]|string
---@param view? table
---@return table|nil, string|nil
function M.resolve_review_context(args, view)
  local existing = M.review_context_for_view(view)
  if existing and is_empty_args(args) then
    return existing, nil
  end

  local root = nil
  if type(view) == "table" then
    for _, key in ipairs(ROOT_CANDIDATE_KEYS) do
      root = normalize_root_candidate(view[key])
      if root then
        break
      end
    end
  end
  root = root or normalize_root_candidate(git_root())
  if not root then
    return nil, "not_git_repo"
  end

  local revisions = revisions_from_args(args)
  if not revisions and type(view) == "table" then
    revisions = revisions_from_view(view)
  end
  if not revisions and existing and type(existing.revisions) == "table" then
    revisions = vim.deepcopy(existing.revisions)
  end

  local mode = revisions and #revisions > 0 and "commit_range" or "working_tree"
  -- Keep a stable review scope across Diffview range lenses so draft comments
  -- persist like GitHub review comments until anchors become outdated.
  local context_id = ("%s::review"):format(root)
  local revision_anchors = resolve_revision_anchors(root, revisions)

  local context = {
    mode = mode,
    root = root,
    revisions = revisions,
    revision_anchors = revision_anchors,
    context_id = context_id,
  }
  if type(view) == "table" then
    M.set_review_context_for_view(view, context)
  end
  return context, nil
end

--- mark view buffers.
local function mark_view_buffers()
  local ok, lib = pcall(require, "diffview.lib")
  if not ok then
    return
  end
  local view = lib.get_current_view()
  if type(view) ~= "table" then
    return
  end
  local entry = view.cur_entry
  if type(entry) ~= "table" or type(entry.layout) ~= "table" then
    return
  end
  for _, slot in pairs(entry.layout) do
    local file = slot and slot.file or nil
    local bufnr = file and file.bufnr or nil
    mark_buffer(bufnr)
  end
end

--- sync comments for view.
local function sync_comments_for_view()
  local ok, comments = pcall(require, "commentry.comments")
  if not ok then
    return
  end
  if type(comments.load_current_view) == "function" then
    comments.load_current_view()
  end
  if type(comments.render_current_buffer) == "function" then
    comments.render_current_buffer()
  end
  if type(comments.refresh_hover_preview) == "function" then
    comments.refresh_hover_preview()
  end
end

---@param bufnr integer
local function is_diff_buffer(bufnr)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  local is_diff = vim.b[bufnr].commentry_diffview
  if is_diff == nil then
    local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, "commentry_diffview")
    if ok then
      is_diff = value
    end
  end
  return is_diff == true
end

--- refresh hover for current buffer.
local function refresh_hover_for_current_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  if not is_diff_buffer(bufnr) then
    M.clear_hover_preview(bufnr)
    return
  end
  local ok, comments = pcall(require, "commentry.comments")
  if not ok or type(comments.refresh_hover_preview) ~= "function" then
    M.clear_hover_preview(bufnr)
    return
  end
  comments.refresh_hover_preview()
end

---@param bufnr integer
local function ensure_hover_autocmd(bufnr)
  if type(bufnr) ~= "number" or hover_attached[bufnr] then
    return
  end
  hover_attached[bufnr] = true
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorHold" }, {
    group = Config.augroup,
    buffer = bufnr,
    callback = function()
      refresh_hover_for_current_buffer()
    end,
  })
end

---@return boolean
function M.is_available()
  return pcall(require, "diffview")
end

---@param args? string[]|string
---@param review_context? table
---@return boolean, string|nil
function M.open(args, review_context)
  local ok, diffview = pcall(require, "diffview")
  if not ok then
    return false, "diffview.nvim is required"
  end
  if is_empty_args(args) then
    local root = git_root()
    if not root then
      return false, "not_git_repo"
    end
    local changed, err = has_local_changes(root)
    if changed == nil then
      return false, err
    end
    if not changed then
      return false, "no_changes"
    end
  end
  if type(args) == "string" then
    args = { args }
  end
  local context = review_context
  if type(context) ~= "table" then
    context = M.resolve_review_context(args)
  end
  diffview.open(args or {})
  vim.schedule(function()
    local view = M.get_current_view()
    if type(view) == "table" and type(context) == "table" then
      M.set_review_context_for_view(view, context)
    end
    mark_view_buffers()
    sync_comments_for_view()
  end)
  return true, nil
end

---@return boolean
function M.mark_current_buffer()
  local context = M.current_file_context()
  if not context then
    return false
  end
  mark_buffer(context.bufnr)
  ensure_hover_autocmd(context.bufnr)
  return true
end

--- setup.
function M.setup()
  if not Config.diffview.auto_attach then
    return
  end
  vim.api.nvim_create_autocmd("User", {
    group = Config.augroup,
    pattern = "DiffviewViewPostLayout",
    callback = function()
      mark_view_buffers()
      vim.schedule(sync_comments_for_view)
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = Config.augroup,
    pattern = "DiffviewDiffBufWinEnter",
    callback = function()
      M.mark_current_buffer()
      vim.schedule(sync_comments_for_view)
    end,
  })
end

---@return any|nil, string|nil
function M.get_current_view()
  local ok, lib = pcall(require, "diffview.lib")
  if not ok then
    return nil, "diffview.nvim is required"
  end
  return lib.get_current_view(), nil
end

---@return table|nil, string|nil
function M.current_file_context()
  local view, err = M.get_current_view()
  if not view then
    return nil, err
  end

  local entry = view.cur_entry
  if type(entry) ~= "table" or type(entry.layout) ~= "table" then
    return nil, "diffview has no active file entry"
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local side = nil
  for _, key in ipairs({ "a", "b", "c", "d" }) do
    local slot = entry.layout[key]
    if slot and slot.file and slot.file.bufnr == bufnr then
      side = key
      break
    end
  end

  if not side then
    return nil, "current buffer is not a diffview file buffer"
  end

  local line_side = side == "a" and "base" or side == "b" and "head" or nil
  if not line_side then
    return nil, ("unsupported diffview side: %s"):format(side)
  end

  return {
    file_path = entry.path,
    line_number = vim.api.nvim_win_get_cursor(0)[1],
    line_side = line_side,
    bufnr = bufnr,
    view = view,
  },
    nil
end

---@param view? table
---@return string[]
function M.list_view_files(view)
  if type(view) ~= "table" then
    return {}
  end

  local seen = {}
  local files = {}
  local function push(path)
    if type(path) ~= "string" or path == "" or seen[path] then
      return
    end
    seen[path] = true
    files[#files + 1] = path
  end

  if type(view.files) == "table" and type(view.files.iter) == "function" then
    for _, file in view.files:iter() do
      if type(file) == "table" then
        push(file.path)
      end
    end
  elseif type(view.panel) == "table" and type(view.panel.ordered_file_list) == "function" then
    local ok, ordered = pcall(view.panel.ordered_file_list, view.panel)
    if ok and type(ordered) == "table" then
      for _, file in ipairs(ordered) do
        if type(file) == "table" then
          push(file.path)
        end
      end
    end
  end

  if type(view.cur_entry) == "table" then
    push(view.cur_entry.path)
  end

  return files
end

---@param view table
---@param path string
---@return table|nil
local function find_file_entry(view, path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if type(view.files) == "table" and type(view.files.iter) == "function" then
    for _, file in view.files:iter() do
      if type(file) == "table" and file.path == path then
        return file
      end
    end
  end
  return nil
end

---@param view? table
---@param path string
---@return boolean, string|nil
function M.focus_file(view, path)
  if type(view) ~= "table" then
    return false, "view_unavailable"
  end
  if type(path) ~= "string" or path == "" then
    return false, "file_path_required"
  end
  if type(view.cur_entry) == "table" and view.cur_entry.path == path then
    return true, nil
  end

  if type(view.set_file_by_path) == "function" then
    local ok = pcall(view.set_file_by_path, view, path, true, true)
    if ok then
      return true, nil
    end
  end

  local entry = find_file_entry(view, path)
  if type(view.set_file) == "function" and entry then
    local ok = pcall(view.set_file, view, entry, true, true)
    if ok then
      return true, nil
    end
  end

  return false, "unable_to_focus_file"
end

---@param bufnr integer
---@param comments commentry.DraftComment[]
function M.render_comment_markers(bufnr, comments)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, Config.ns, 0, -1)

  if type(comments) ~= "table" then
    return
  end

  local counts = {}
  for _, comment in ipairs(comments) do
    if type(comment) == "table" then
      local line_start = comment.line_start or comment.line_number
      if type(line_start) == "number" and line_start > 0 then
        local key = line_start
        if not counts[key] then
          counts[key] = { total = 0, by_type = {} }
        end
        counts[key].total = counts[key].total + 1
        local comment_type = comment.comment_type or "note"
        counts[key].by_type[comment_type] = (counts[key].by_type[comment_type] or 0) + 1
      end
    end
  end

  for line_number, group in pairs(counts) do
    local types = vim.tbl_keys(group.by_type)
    table.sort(types)
    local label = nil
    if #types == 1 then
      local only_type = types[1]
      local count = group.by_type[only_type]
      label = count == 1 and ("[%s]"):format(only_type) or ("[%s:%d]"):format(only_type, count)
    else
      local pieces = {}
      for _, comment_type in ipairs(types) do
        local count = group.by_type[comment_type]
        if count == 1 then
          pieces[#pieces + 1] = comment_type
        else
          pieces[#pieces + 1] = ("%s:%d"):format(comment_type, count)
        end
      end
      label = ("[%s]"):format(table.concat(pieces, ","))
    end
    local line = math.max(line_number - 1, 0)
    pcall(vim.api.nvim_buf_set_extmark, bufnr, Config.ns, line, 0, {
      virt_text = { { label, "Comment" } },
      virt_text_pos = "eol",
      hl_mode = "combine",
    })
  end
end

---@param bufnr integer
---@param reviewed boolean
function M.render_file_review_indicator(bufnr, reviewed)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, file_review_ns, 0, -1)
  local label = reviewed and "[reviewed]" or "[unreviewed]"
  pcall(vim.api.nvim_buf_set_extmark, bufnr, file_review_ns, 0, 0, {
    virt_text = { { label, "Comment" } },
    virt_text_pos = "right_align",
    hl_mode = "combine",
  })
end

---@param bufnr integer
function M.clear_hover_preview(bufnr)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, hover_ns, 0, -1)
end

---@param bufnr integer
---@param line_number integer
---@param comments commentry.DraftComment[]
function M.render_hover_preview(bufnr, line_number, comments)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  M.clear_hover_preview(bufnr)
  if type(line_number) ~= "number" or line_number < 1 then
    return
  end
  if type(comments) ~= "table" or #comments == 0 then
    return
  end

  local virt_lines = {}
  for _, comment in ipairs(comments) do
    if type(comment) == "table" and type(comment.body) == "string" and comment.body ~= "" then
      local body = comment.body:gsub("\n", " ")
      local comment_type = comment.comment_type or "note"
      virt_lines[#virt_lines + 1] = { { ("[%s] %s"):format(comment_type, body), "Comment" } }
    end
  end
  if #virt_lines == 0 then
    return
  end

  local line = math.max(line_number - 1, 0)
  pcall(vim.api.nvim_buf_set_extmark, bufnr, hover_ns, line, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    hl_mode = "combine",
  })
end

return M
