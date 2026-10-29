-- Diffview is a capture surface for the inbox, not a separate review store.
local M = {}
local Config = require("commentry.config")
local pending = false
local initialized = false

function M.get_current_view()
  local ok, lib = pcall(require, "diffview.lib")
  return ok and lib.get_current_view() or nil
end

-- Use the file object for the displayed side. entry.path can be the new name
-- of a rename, and scratch-buffer names are not filesystem paths.
function M.current_file_context(buf)
  local view = M.get_current_view()
  local entry = view and view.cur_entry
  if not entry or not entry.layout then
    return nil
  end
  buf = buf or vim.api.nvim_get_current_buf()
  for _, side in ipairs({ "a", "b", "c", "d" }) do
    local slot = entry.layout[side]
    local file = slot and slot.file
    if file and file.bufnr == buf and not file.nulled and not file.binary then
      local root = file.adapter and file.adapter.ctx and file.adapter.ctx.toplevel
      if not root then
        return nil
      end
      return {
        project = (vim.uv or vim.loop).fs_realpath(root) or vim.fs.normalize(root),
        file_path = file.path,
        bufnr = buf,
        side = side,
        file = file,
        view = view,
      }
    end
  end
end

function M.capture(buf, first, last)
  local context = M.current_file_context(buf)
  if not context then
    return nil, "Select a nonempty text file in Diffview"
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if first < 1 or last < first or last > #lines then
    return nil, "Invalid capture range"
  end
  local file, project = context.file, context.project
  local rev = file.rev
  local git = {}
  local function read(args)
    local command = { "git", "-C", project }
    vim.list_extend(command, args)
    local result = vim.system(command, { text = true }):wait()
    return result.code == 0 and vim.trim(result.stdout) or nil
  end
  git.head = read({ "rev-parse", "HEAD" })
  git.branch = read({ "branch", "--show-current" })
  -- A commit or index capture keeps its actual displayed baseline. The saved
  -- lines remain authoritative even if the index or working tree changes later.
  if rev and rev.commit then
    git.revision = rev.commit
    git.blob = read({ "rev-parse", rev.commit .. ":" .. file.path })
  elseif rev and rev.stage ~= nil then
    git.revision = ":" .. rev.stage
    git.blob = read({ "rev-parse", ":" .. rev.stage .. ":" .. file.path })
  else
    git.revision = "working-tree"
  end
  return {
    project = project,
    source = {
      kind = "file",
      path = file.path,
      first = first,
      last = last,
      lines = lines,
      filetype = vim.bo[buf].filetype,
      modified = vim.bo[buf].modified,
      origin = "diffview:" .. context.side,
      git = git,
    },
  }
end

function M.refresh()
  local context = M.current_file_context()
  -- Layout events often arrive with focus on the file panel.
  if not context then
    local view = M.get_current_view()
    local entry = view and view.cur_entry
    for _, slot in pairs(entry and entry.layout or {}) do
      if type(slot) == "table" and slot.file and slot.file.bufnr then
        context = M.current_file_context(slot.file.bufnr)
        if context then
          break
        end
      end
    end
  end
  if not context then
    return
  end
  local threads, err = require("commentry.inbox.store").list(context.project)
  if not threads then
    require("commentry.util").warn(err)
    return
  end
  require("commentry.inbox.render").highlights()
  require("commentry.inbox.locations").set(threads)
end

local function attach()
  local view = M.get_current_view()
  local entry = view and view.cur_entry
  for _, slot in pairs(entry and entry.layout or {}) do
    if type(slot) == "table" and slot.file and slot.file.bufnr then
      local buf = slot.file.bufnr
      require("commentry.commands").attach(buf)
      require("commentry.inbox.locations").draw(buf)
    end
  end
end

function M.open(args)
  if not Config.diffview.enabled then
    return false, "Diffview is disabled"
  end
  local ok, diffview = pcall(require, "diffview")
  if not ok then
    return false, "Install diffview.nvim to use :Commentry open"
  end
  diffview.open(args or {})
  return true
end

function M.setup()
  if initialized or not Config.diffview.enabled or not Config.diffview.auto_attach then
    return
  end
  initialized = true
  vim.api.nvim_create_autocmd("User", {
    group = Config.augroup,
    pattern = { "DiffviewViewPostLayout", "DiffviewDiffBufRead", "DiffviewDiffBufWinEnter" },
    desc = "Attach inbox comments to Diffview",
    callback = function()
      attach()
      if pending then
        return
      end
      pending = true
      -- A layout emits several events. Fetch the shared inbox once per burst.
      vim.defer_fn(function()
        pending = false
        if not M.get_current_view() then
          return
        end
        attach()
        M.refresh()
      end, 100)
    end,
  })
end

function M.debug_state()
  local context = M.current_file_context()
  return { attached = context ~= nil, bufnr = vim.api.nvim_get_current_buf(), project = context and context.project }
end

return M
