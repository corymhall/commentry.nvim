local M = {}

local Config = require("commentry.config")
local file_review_ns = vim.api.nvim_create_namespace("commentry-file-review")
local uv = vim.uv or vim.loop
local ROOT_CANDIDATE_KEYS = { "git_root", "toplevel", "root", "cwd", "path" }
local view_context_by_tabpage = {}
local setup_done = false

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
---@return string|nil
local function git_branch_id(root)
  if type(root) ~= "string" or root == "" then
    return nil
  end

  local branch = vim.fn.systemlist({ "git", "-C", root, "symbolic-ref", "--short", "HEAD" })[1]
  if vim.v.shell_error == 0 and type(branch) == "string" and branch ~= "" then
    return branch
  end

  local short = vim.fn.systemlist({ "git", "-C", root, "rev-parse", "--short", "HEAD" })[1]
  if vim.v.shell_error == 0 and type(short) == "string" and short ~= "" then
    return ("detached-%s"):format(short)
  end

  return nil
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
  -- Keep a stable review scope across Diffview range lenses for a branch so
  -- draft comments persist until anchors become outdated.
  local branch_id = git_branch_id(root) or "unknown"
  local context_id = ("%s::review::branch::%s"):format(root, branch_id)
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
  return true
end

--- setup.
function M.setup()
  if setup_done then
    return
  end
  if not Config.diffview.auto_attach then
    return
  end
  setup_done = true
  M.ensure_highlights()
  vim.api.nvim_create_autocmd("User", {
    group = Config.augroup,
    pattern = "DiffviewViewPostLayout",
    desc = "Commentry sync comments after diffview layout",
    callback = function()
      mark_view_buffers()
      sync_comments_for_view()
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = Config.augroup,
    pattern = "DiffviewDiffBufRead",
    desc = "Commentry mark/sync on diff buffer read",
    callback = function()
      M.mark_current_buffer()
      sync_comments_for_view()
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = Config.augroup,
    pattern = "DiffviewDiffBufWinEnter",
    desc = "Commentry mark/sync on diff buffer enter",
    callback = function()
      M.mark_current_buffer()
      sync_comments_for_view()
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

---@param view? table
---@param line_side string
---@return boolean, string|nil
function M.focus_file_side(view, line_side)
  if type(view) ~= "table" then
    return false, "view_unavailable"
  end
  if line_side ~= "base" and line_side ~= "head" then
    return false, "line_side_required"
  end
  if type(view.cur_entry) ~= "table" or type(view.cur_entry.layout) ~= "table" then
    return false, "entry_layout_unavailable"
  end

  local side_key = line_side == "base" and "a" or "b"
  local slot = view.cur_entry.layout[side_key]
  if type(slot) ~= "table" then
    return false, "target_side_unavailable"
  end

  local winid = slot.winid
  if type(winid) == "number" and winid > 0 and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_set_current_win(winid)
    return true, nil
  end

  local bufnr = slot.file and slot.file.bufnr or nil
  if type(bufnr) == "number" and bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
    local bufwin = vim.fn.bufwinid(bufnr)
    if type(bufwin) == "number" and bufwin > 0 and vim.api.nvim_win_is_valid(bufwin) then
      vim.api.nvim_set_current_win(bufwin)
      return true, nil
    end
  end

  return false, "target_window_unavailable"
end

local TYPE_LABEL = {
  note = "NOTE",
  suggestion = "SUGGESTION",
  issue = "ISSUE",
  praise = "PRAISE",
}

local TYPE_HL = {
  note = { border = "CommentryBorderNote", tag = "CommentryTypeNote" },
  suggestion = { border = "CommentryBorderSuggestion", tag = "CommentryTypeSuggestion" },
  issue = { border = "CommentryBorderIssue", tag = "CommentryTypeIssue" },
  praise = { border = "CommentryBorderPraise", tag = "CommentryTypePraise" },
}

local TYPE_PRIORITY = {
  issue = 4,
  suggestion = 3,
  note = 2,
  praise = 1,
}

---@return table
local function comment_card_config()
  local cfg = ((Config.diffview or {}).comment_cards or {})
  return {
    max_width = math.max(24, tonumber(cfg.max_width) or 88),
    max_body_lines = math.max(1, tonumber(cfg.max_body_lines) or 8),
    show_markers = cfg.show_markers ~= false,
  }
end

---@return table
local function comment_range_config()
  local cfg = ((Config.diffview or {}).comment_ranges or {})
  return {
    enabled = cfg.enabled ~= false,
    line_highlight = cfg.line_highlight ~= false,
  }
end

---@param comment_type string
---@return table
local function type_hl(comment_type)
  return TYPE_HL[comment_type] or TYPE_HL.note
end

---@param comment_type string
---@return string
local function type_label(comment_type)
  return TYPE_LABEL[comment_type] or comment_type:upper()
end

---@param comment table
---@return integer
local function line_start(comment)
  return comment.line_start or comment.line_number or 1
end

---@param comment table
---@return integer
local function line_end(comment)
  return comment.line_end or line_start(comment)
end

---@param comment table
---@return string
local function line_label(comment)
  local first = line_start(comment)
  local last = line_end(comment)
  if last <= first then
    return ("L%d"):format(first)
  end
  return ("L%d-L%d"):format(first, last)
end

---@param text string
---@param max_width integer
---@return string[]
local function wrap_text(text, max_width)
  local limit = math.max(12, max_width)
  if #text <= limit then
    return { text }
  end
  local out = {}
  local start = 1
  while start <= #text do
    out[#out + 1] = text:sub(start, start + limit - 1)
    start = start + limit
  end
  return out
end

---@param by_type table<string, integer>
---@return string
local function marker_label(by_type)
  local types = vim.tbl_keys(by_type)
  table.sort(types)
  if #types == 1 then
    local only_type = types[1]
    local count = by_type[only_type]
    if count == 1 then
      return ("[%s]"):format(only_type)
    end
    return ("[%s:%d]"):format(only_type, count)
  end
  local pieces = {}
  for _, comment_type in ipairs(types) do
    local count = by_type[comment_type]
    if count == 1 then
      pieces[#pieces + 1] = comment_type
    else
      pieces[#pieces + 1] = ("%s:%d"):format(comment_type, count)
    end
  end
  return ("[%s]"):format(table.concat(pieces, ","))
end

---@param comment table
---@param cfg table
---@return table[]
local function card_lines_for_comment(comment, cfg)
  local comment_type = comment.comment_type or "note"
  local hl = type_hl(comment_type)
  local max_body_width = math.max(12, cfg.max_width - 6)
  local range = line_label(comment)
  local header = ("[%s] %s"):format(type_label(comment_type), range)
  local lines = {
    { { "  ╭─ ", hl.border }, { header, hl.tag } },
  }

  local body_lines = vim.split(comment.body or "", "\n", { plain = true })
  if #body_lines == 0 then
    body_lines = { "" }
  end
  local rendered = 0
  for _, body_line in ipairs(body_lines) do
    for _, segment in ipairs(wrap_text(body_line, max_body_width)) do
      if rendered >= cfg.max_body_lines then
        break
      end
      lines[#lines + 1] = { { "  │ ", hl.border }, { segment, "CommentryBody" } }
      rendered = rendered + 1
    end
    if rendered >= cfg.max_body_lines then
      break
    end
  end
  if rendered == cfg.max_body_lines and #body_lines > 0 then
    lines[#lines + 1] = { { "  │ ", hl.border }, { "...", "CommentryBody" } }
  end

  lines[#lines + 1] = { { "  ╰" .. string.rep("─", math.max(10, #header + 1)), hl.border } }
  return lines
end

function M.ensure_highlights()
  pcall(vim.api.nvim_set_hl, 0, "CommentryMarker", { link = "Comment" })
  pcall(vim.api.nvim_set_hl, 0, "CommentryBody", { link = "Comment" })
  pcall(vim.api.nvim_set_hl, 0, "CommentryBorderNote", { link = "Comment" })
  pcall(vim.api.nvim_set_hl, 0, "CommentryTypeNote", { link = "Comment" })
  pcall(vim.api.nvim_set_hl, 0, "CommentryBorderSuggestion", { link = "DiagnosticHint" })
  pcall(vim.api.nvim_set_hl, 0, "CommentryTypeSuggestion", { link = "DiagnosticHint" })
  pcall(vim.api.nvim_set_hl, 0, "CommentryBorderIssue", { link = "DiagnosticError" })
  pcall(vim.api.nvim_set_hl, 0, "CommentryTypeIssue", { link = "DiagnosticError" })
  pcall(vim.api.nvim_set_hl, 0, "CommentryBorderPraise", { link = "DiagnosticOk" })
  pcall(vim.api.nvim_set_hl, 0, "CommentryTypePraise", { link = "DiagnosticOk" })
  pcall(vim.api.nvim_set_hl, 0, "CommentryRangeLineNote", { link = "CursorLine" })
  pcall(vim.api.nvim_set_hl, 0, "CommentryRangeLineSuggestion", { link = "CursorLine" })
  pcall(vim.api.nvim_set_hl, 0, "CommentryRangeLineIssue", { link = "CursorLine" })
  pcall(vim.api.nvim_set_hl, 0, "CommentryRangeLinePraise", { link = "CursorLine" })
  pcall(vim.api.nvim_set_hl, 0, "CommentryRangeSignNote", { link = "CommentryBorderNote" })
  pcall(vim.api.nvim_set_hl, 0, "CommentryRangeSignSuggestion", { link = "CommentryBorderSuggestion" })
  pcall(vim.api.nvim_set_hl, 0, "CommentryRangeSignIssue", { link = "CommentryBorderIssue" })
  pcall(vim.api.nvim_set_hl, 0, "CommentryRangeSignPraise", { link = "CommentryBorderPraise" })
end

---@param comment_type string
---@return string
local function range_sign_hl(comment_type)
  local suffix = (comment_type == "issue" or comment_type == "suggestion" or comment_type == "praise") and comment_type
    or "note"
  return "CommentryRangeSign" .. suffix:sub(1, 1):upper() .. suffix:sub(2)
end

---@param comment_type string
---@return string
local function range_line_hl(comment_type)
  local suffix = (comment_type == "issue" or comment_type == "suggestion" or comment_type == "praise") and comment_type
    or "note"
  return "CommentryRangeLine" .. suffix:sub(1, 1):upper() .. suffix:sub(2)
end

---@param kind string
---@return string
local function range_sign_text(kind)
  if kind == "start" then
    return "╭"
  end
  if kind == "end" then
    return "╰"
  end
  if kind == "single" then
    return "●"
  end
  return "│"
end

---@param existing table|nil
---@param candidate table
---@return table
local function preferred_decoration(existing, candidate)
  if not existing then
    return candidate
  end
  local existing_priority = TYPE_PRIORITY[existing.comment_type or "note"] or 0
  local candidate_priority = TYPE_PRIORITY[candidate.comment_type or "note"] or 0
  if candidate_priority > existing_priority then
    return candidate
  end
  return existing
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

  M.ensure_highlights()
  local cfg = comment_card_config()
  local range_cfg = comment_range_config()
  local counts = {}
  local comments_by_line = {}
  local range_decorations = {}
  for _, comment in ipairs(comments) do
    if type(comment) == "table" then
      local anchor_line = line_start(comment)
      if type(anchor_line) == "number" and anchor_line > 0 then
        local key = anchor_line
        if not counts[key] then
          counts[key] = { total = 0, by_type = {} }
        end
        counts[key].total = counts[key].total + 1
        local comment_type = comment.comment_type or "note"
        counts[key].by_type[comment_type] = (counts[key].by_type[comment_type] or 0) + 1
        comments_by_line[key] = comments_by_line[key] or {}
        comments_by_line[key][#comments_by_line[key] + 1] = comment
      end

      if range_cfg.enabled then
        local first = math.max(line_start(comment), 1)
        local last = math.max(line_end(comment), first)
        local comment_type = comment.comment_type or "note"
        if first == last then
          range_decorations[first] = preferred_decoration(range_decorations[first], {
            comment_type = comment_type,
            kind = "single",
          })
        else
          for line_number = first, last do
            local kind = "mid"
            if line_number == first then
              kind = "start"
            elseif line_number == last then
              kind = "end"
            end
            range_decorations[line_number] = preferred_decoration(range_decorations[line_number], {
              comment_type = comment_type,
              kind = kind,
            })
          end
        end
      end
    end
  end

  if range_cfg.enabled then
    for line_number, decoration in pairs(range_decorations) do
      local line = math.max(line_number - 1, 0)
      local opts = {
        sign_text = range_sign_text(decoration.kind),
        sign_hl_group = range_sign_hl(decoration.comment_type),
      }
      if range_cfg.line_highlight then
        opts.line_hl_group = range_line_hl(decoration.comment_type)
      end
      pcall(vim.api.nvim_buf_set_extmark, bufnr, Config.ns, line, 0, opts)
    end
  end

  local lines = vim.tbl_keys(counts)
  table.sort(lines)
  for _, line_number in ipairs(lines) do
    local group = counts[line_number]
    local line = math.max(line_number - 1, 0)
    if cfg.show_markers then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, Config.ns, line, 0, {
        virt_text = { { marker_label(group.by_type), "CommentryMarker" } },
        virt_text_pos = "eol",
        hl_mode = "combine",
      })
    end

    local line_comments = comments_by_line[line_number] or {}
    table.sort(line_comments, function(a, b)
      if (a.created_at or "") ~= (b.created_at or "") then
        return (a.created_at or "") < (b.created_at or "")
      end
      return (a.id or "") < (b.id or "")
    end)

    local virt_lines = {}
    for index, comment in ipairs(line_comments) do
      for _, vline in ipairs(card_lines_for_comment(comment, cfg)) do
        virt_lines[#virt_lines + 1] = vline
      end
      if index < #line_comments then
        virt_lines[#virt_lines + 1] = { { " ", "CommentryBody" } }
      end
    end

    pcall(vim.api.nvim_buf_set_extmark, bufnr, Config.ns, line, 0, {
      virt_lines = virt_lines,
      virt_lines_above = false,
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

---@param _bufnr integer
function M.clear_hover_preview(_bufnr)
  return
end

---@param _bufnr integer
---@param _line_number integer
---@param _comments commentry.DraftComment[]
function M.render_hover_preview(_bufnr, _line_number, _comments)
  return
end

return M
