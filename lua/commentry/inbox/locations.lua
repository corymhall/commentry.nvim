local Source = require("commentry.inbox.source")
local M = {}
local ns = vim.api.nvim_create_namespace("commentry.inbox.locations")
local threads, current = {}, nil
local initialized = false
local visited = {}

local function locations(thread)
  local items = Source.locations(thread)
  local source = visited[thread.id]
  if source then
    for _, item in ipairs(items) do
      if vim.deep_equal(item.source, source) then
        return items
      end
    end
    items[#items + 1] = { source = source }
  end
  return items
end

local function display(buf)
  local context = require("commentry.diffview").current_file_context(buf)
  if context then
    return vim.fs.joinpath(context.project, context.file_path), vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  return vim.api.nvim_buf_get_name(buf),
    vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_lines(buf, 0, -1, false) or nil
end

function M.draw(buf)
  if not vim.api.nvim_buf_is_loaded(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local path, contents = display(buf)
  if vim.bo[buf].buftype ~= "" and not contents then
    return
  end
  local cards, seen = {}, {}
  for _, thread in ipairs(threads) do
    if not thread.resolved or thread.id == current then
      for _, attachment in ipairs(locations(thread)) do
        local source = attachment.source
        if source.kind == "file" and vim.fs.joinpath(thread.project, source.path) == path then
          local target = Source.locate(vim.tbl_extend("force", thread, { source = source }), contents)
          if target then
            local key = thread.id .. ":" .. target.first .. ":" .. target.last
            if not seen[key] then
              cards[#cards + 1] = { thread = thread, first = target.first, last = target.last }
              seen[key] = true
            end
          end
        end
      end
    end
  end
  if contents then
    require("commentry.inbox.cards").draw(buf, ns, cards)
    if #cards > 0 then
      vim.api.nvim_buf_call(buf, function()
        if vim.fn.maparg("gC", "n") == "" then
          vim.keymap.set("n", "gC", M.open_at_cursor, { buffer = buf, desc = "Open inbox thread at cursor" })
        end
      end)
    end
  end
end

function M.choose_at_cursor(callback)
  local path, contents = display(vim.api.nvim_get_current_buf())
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local candidates, seen = {}, {}
  for _, thread in ipairs(threads) do
    for _, attachment in ipairs(locations(thread)) do
      if attachment.source.kind == "file" and vim.fs.joinpath(thread.project, attachment.source.path) == path then
        local target = Source.locate(vim.tbl_extend("force", thread, { source = attachment.source }), contents)
        if target and row >= target.first and row <= target.last and not seen[thread.id] then
          candidates[#candidates + 1], seen[thread.id] = thread, true
        end
      end
    end
  end
  if #candidates == 1 then
    callback(candidates[1])
  elseif #candidates > 1 then
    vim.ui.select(candidates, {
      prompt = "Code conversations",
      format_item = function(t)
        return t.title
      end,
    }, callback)
  else
    require("commentry.util").info("No inbox thread at this line")
  end
end

function M.open_at_cursor()
  M.choose_at_cursor(function(thread)
    if thread then
      require("commentry.inbox").open(nil, { project = thread.project, thread = thread.id })
    end
  end)
end

function M.set(items, selected)
  threads, current = items, selected
  local present = {}
  for _, thread in ipairs(items) do
    present[thread.id] = true
  end
  for id in pairs(visited) do
    if not present[id] then
      visited[id] = nil
    end
  end
  if not initialized then
    initialized = true
    local group = vim.api.nvim_create_augroup("CommentryInboxLocations", { clear = true })
    vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
      group = group,
      desc = "Refresh cached inbox code locations",
      callback = function(event)
        M.draw(event.buf)
      end,
    })
    vim.keymap.set("n", "<Plug>(CommentryThread)", M.open_at_cursor, { desc = "Open inbox thread at cursor" })
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    M.draw(buf)
  end
end

function M.jump(thread, win)
  local target, err = Source.locate(thread)
  if not target then
    return nil, err
  end
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd.tabnew()
  end
  local buf = vim.fn.bufadd(target.path)
  vim.fn.bufload(buf)
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, { target.first, 0 })
  -- A live section can show code newer than its saved attachment. Retain this
  -- visited snapshot for markers and gC without mutating the stored capture.
  visited[thread.id] = thread.source
  vim.cmd("normal! zz")
  -- Only claim a free buffer-local shortcut. The Plug action is always available.
  if vim.fn.maparg("gC", "n") == "" then
    vim.keymap.set("n", "gC", M.open_at_cursor, { buffer = buf, desc = "Open inbox thread at cursor" })
  end
  M.draw(buf)
  require("commentry.inbox.animate").flash(buf, target.first, target.last)
  return true
end

return M
