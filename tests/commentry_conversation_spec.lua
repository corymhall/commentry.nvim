---@module 'luassert'
local Render = require("commentry.inbox.render")

describe("conversation message presentation", function()
  local buf, win, previous, thread, view

  local function message(id, author, body)
    return { id = id, author = author, body = body, at = "2026-11-12T10:00:00Z" }
  end

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "acwrite"
    win = vim.api.nvim_get_current_win()
    previous = vim.api.nvim_win_get_buf(win)
    vim.api.nvim_win_set_buf(win, buf)
    thread = {
      id = "conversation-" .. buf,
      project = "/fixture",
      title = "A discussion",
      queue = {},
      messages = {
        message("human-1", "You", "First question\nWith more context"),
        message("agent-1", "Agent", "First answer\nWith implementation details"),
        message("human-2", "You", "Latest question"),
        message("agent-2", "Pi", "Latest answer"),
      },
    }
    view = { thread_buf = buf, thread_win = win, outdated = {} }
    Render.highlights()
  end)

  after_each(function()
    vim.bo[buf].modified = false
    vim.api.nvim_win_set_buf(win, previous)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  local function closed(index)
    local section = view.message_presentation.messages[index]
    return vim.fn.foldclosed(section.first) == section.first
  end

  local function toggle(index, command)
    vim.api.nvim_win_set_cursor(win, { view.message_presentation.messages[index].first, 0 })
    vim.cmd("normal! " .. command)
  end

  it("keeps the last human and last agent expanded and folds all older messages including their padding", function()
    thread.messages[#thread.messages + 1] = message("agent-3", "Codex", "Another agent response")
    thread.messages[#thread.messages + 1] = message("human-3", "You", "A follow-up from me")
    Render.conversation(view, thread)
    for index = 1, 4 do
      assert.is_true(closed(index))
    end
    assert.is_false(closed(5))
    assert.is_false(closed(6))
    local first = view.message_presentation.messages[1]
    assert.is_truthy(vim.fn.foldtextresult(first.first):find("First question", 1, true))
    assert.is_truthy(vim.fn.foldtextresult(first.first):find("YOU", 1, true))
    assert.are.same(first.last, vim.fn.foldclosedend(first.first))
    assert.are.same("", vim.api.nvim_buf_get_lines(buf, first.last - 1, first.last, false)[1])
    assert.are.same(-1, vim.fn.foldclosed(#view.reply.prefix + 1))
    assert.is_truthy(
      table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("With more context", 1, true)
    )
  end)

  it(
    "folds the previous latest message when a new reply arrives and preserves explicit fold choices across switches",
    function()
      Render.conversation(view, thread)
      toggle(1, "zo")
      thread.messages[#thread.messages + 1] = message("human-3", "You", "A new question")
      thread.messages[#thread.messages + 1] = message("agent-3", "Agent", "A new answer")
      Render.conversation(view, thread)
      assert.is_false(closed(1))
      assert.is_true(closed(2))
      assert.is_true(closed(3))
      assert.is_true(closed(4))
      assert.is_false(closed(5))
      assert.is_false(closed(6))
      local other = vim.tbl_extend("force", thread, {
        id = thread.id .. "-other",
        messages = { message("other", "You", "Another topic") },
      })
      Render.conversation(view, other)
      Render.conversation(view, thread)
      assert.is_false(closed(1))
      assert.is_true(closed(3))
      assert.is_false(closed(5))
      assert.is_false(closed(6))
    end
  )

  it("restores draft folds against frozen history instead of messages that arrived while away", function()
    Render.conversation(view, thread)
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "Unsent reply" })
    local frozen = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    thread.messages[#thread.messages + 1] = message("agent-3", "Agent", "Not displayed while editing")
    Render.conversation(view, thread)
    assert.are.same(frozen, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    local other = vim.tbl_extend("force", thread, {
      id = thread.id .. "-other",
      messages = { message("other", "You", "Another topic") },
    })
    Render.conversation(view, other)
    Render.conversation(view, thread)
    assert.is_true(vim.bo[buf].modified)
    assert.are.same(frozen, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    assert.is_true(closed(1))
    assert.is_true(closed(2))
    assert.is_false(closed(3))
    assert.is_false(closed(4))
    assert.are.same(-1, vim.fn.foldclosed(#view.reply.prefix + 1))
  end)

  it("keeps the latest message open when only one role has posted", function()
    thread.messages = {
      message("only-1", "You", "First note"),
      message("only-2", "You", "Latest note"),
    }
    Render.conversation(view, thread)
    assert.is_true(closed(1))
    assert.is_false(closed(2))
  end)
end)
