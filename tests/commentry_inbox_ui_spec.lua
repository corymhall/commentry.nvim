---@module 'luassert'
local Bridge = require("commentry.dev.ui_bridge").Bridge

describe("inbox embedded UI", function()
  local bridge, directory
  local function exec(code, args)
    return bridge:request("nvim_exec_lua", { code, args or {} }, 5000)
  end

  before_each(function()
    directory = vim.fn.tempname()
    vim.fn.mkdir(directory, "p")
    bridge = Bridge.new({
      cmd = vim.v.progpath,
      args = { "--embed", "--headless", "--clean", "-u", "NONE", "-i", "NONE" },
      cwd = directory,
      env = { COMMENTRY_INBOX_DIR = directory .. "/inbox" },
      width = 180,
      height = 30,
    })
    bridge:request("nvim_ui_attach", { 180, 30, { rgb = true, ext_linegrid = true, ext_multigrid = true } }, 5000)
    local nui = vim.api.nvim_get_runtime_file("lua/nui/popup/init.lua", false)[1]
    assert(nui, "nui.nvim must be installed by the test harness")
    exec(
      [[
      local root, nui = ...
      vim.opt.runtimepath:prepend(root)
      vim.opt.runtimepath:prepend(nui)
      vim.env.PATH = root .. "/bin:" .. vim.env.PATH
      function _G.ui_key(buf, lhs)
        for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
          if map.lhs == lhs then return map.callback() end
        end
        error("Missing mapping " .. lhs)
      end
    ]],
      { vim.fn.getcwd(), nui:gsub("/lua/nui/popup/init.lua$", "") }
    )
  end)

  after_each(function()
    if bridge then
      bridge:close()
    end
    vim.fn.delete(directory, "rf")
  end)

  it("retains an unsaved reply while zooming cycling and resizing across layouts", function()
    exec([[
      local Store = require("commentry.inbox.store")
      _G.thread_id = assert(Store.create({
        project = vim.fn.getcwd(), body = "Question",
        source = { kind = "text", lines = { "Context" } },
      }))
      _G.view = require("commentry.inbox").open("all")
      _G.list_width = vim.api.nvim_win_get_width(view.list_win)
      vim.api.nvim_win_set_width(view.source_win, 50)
      _G.source_width = vim.api.nvim_win_get_width(view.source_win)
      ui_key(view.list_buf, "R")
      assert(vim.api.nvim_win_get_width(view.source_win) == source_width)
      vim.api.nvim_set_current_win(view.thread_win)
      vim.api.nvim_buf_set_lines(view.thread_buf, -1, -1, false, { "Unsaved reply" })
      _G.reply_lines = vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false)
      ui_key(view.thread_buf, "gz")
      assert(view.zoomed and vim.api.nvim_win_get_width(view.thread_win) > 150)
      ui_key(view.thread_buf, "gz")
      assert(not view.zoomed)
      assert(vim.api.nvim_win_get_width(view.source_win) == source_width)
      vim.api.nvim_set_current_win(view.list_win)
      ui_key(view.list_buf, "<Tab>")
      assert(vim.api.nvim_get_current_win() == view.thread_win)
      assert(vim.api.nvim_win_get_position(view.thread_win)[2] < vim.api.nvim_win_get_position(view.source_win)[2])
    ]])
    bridge:request("nvim_ui_try_resize", { 220, 30 }, 5000)
    bridge:wait_for_flush(5000)
    assert.is_true(exec([[
      assert(vim.api.nvim_win_get_width(view.list_win) > list_width)
      assert(vim.deep_equal(reply_lines, vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false)))
      return vim.bo[view.thread_buf].modified
    ]]))
    bridge:request("nvim_ui_try_resize", { 100, 24 }, 5000)
    bridge:wait_for_flush(5000)
    assert.is_true(exec([[
      assert(vim.api.nvim_win_get_position(view.source_win)[2] == vim.api.nvim_win_get_position(view.thread_win)[2])
      assert(vim.deep_equal(reply_lines, vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false)))
      assert(#assert(require("commentry.inbox.store").get(thread_id)).messages == 1)
      ui_key(view.list_buf, "q")
      return true
    ]]))
  end)

  it("adds and removes the source panel without replacing the thread window or acknowledging previews", function()
    exec([[
      local Store = require("commentry.inbox.store")
      _G.plain = assert(Store.create({
        project = vim.fn.getcwd(), body = "Project question",
        source = { kind = "text", origin = "general", lines = {} },
      }))
      _G.other = assert(Store.create({
        project = vim.fn.getcwd(), body = "Another project question",
        source = { kind = "text", origin = "general", lines = {} },
      }))
      _G.view = require("commentry.inbox").open(nil, { thread = plain })
      assert(not vim.api.nvim_win_is_valid(view.source_win))
      assert(#vim.api.nvim_tabpage_list_wins(view.tab) == 2)
      _G.thread_win = view.thread_win
      vim.api.nvim_set_current_win(view.thread_win)
      vim.api.nvim_buf_set_lines(view.thread_buf, -1, -1, false, { "Unsaved reply" })
      _G.reply_lines = vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false)
      assert(Store.update(plain, {
        kind = "comparison", label = "Proposed change", author = "Agent",
        before = "old code\n", after = "new code\n",
      }))
      ui_key(view.list_buf, "R")
      assert(view.thread_win == thread_win)
      assert(vim.api.nvim_win_is_valid(view.source_win))
      assert(vim.api.nvim_win_get_position(view.thread_win)[2] < vim.api.nvim_win_get_position(view.source_win)[2])
      assert(vim.deep_equal(reply_lines, vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false)))
      assert(Store.get(plain).unread)
      vim.api.nvim_win_call(view.thread_win, function() vim.cmd("normal! Gzt") end)
      require("commentry.inbox").open(nil, { thread = other })
      assert(view.thread_win == thread_win)
      assert(not vim.api.nvim_win_is_valid(view.source_win))
      assert(#vim.api.nvim_tabpage_list_wins(view.tab) == 2)
      assert(vim.api.nvim_win_call(view.thread_win, vim.fn.winsaveview).topline == 1)
      assert(Store.get(plain).unread)
      vim.api.nvim_set_current_win(view.list_win)
      ui_key(view.list_buf, "<Tab>")
      assert(vim.api.nvim_get_current_win() == view.thread_win)
      ui_key(view.thread_buf, "<Tab>")
      assert(vim.api.nvim_get_current_win() == view.list_win)
      require("commentry.inbox").open(nil, { thread = plain })
      assert(view.thread_win == thread_win)
      assert(vim.bo[view.thread_buf].modified)
      assert(vim.deep_equal(reply_lines, vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false)))
      _G.source_buf = view.source_buf
      ui_key(view.list_buf, "q")
      assert(not vim.api.nvim_buf_is_valid(source_buf))
    ]])
  end)

  it("shows collapsed message previews beside highlighted headers and preserves text while toggling folds", function()
    exec([[
      local Store = require("commentry.inbox.store")
      local id = assert(Store.create({
        project = vim.fn.getcwd(), body = "Older question to summarize",
        source = { kind = "text", origin = "general", lines = {} },
      }))
      assert(Store.update(id, { kind = "reply", author = "Pi", body = "Older agent answer" }))
      assert(Store.update(id, { kind = "reply", author = "You", body = "Latest question" }))
      assert(Store.update(id, { kind = "reply", author = "Pi", body = "Latest answer" }))
      _G.view = require("commentry.inbox").open(nil, { thread = id })
      local first = view.message_presentation.messages[1].first
      assert(vim.api.nvim_win_call(view.thread_win, function() return vim.fn.foldclosed(first) end) == first)
    ]])
    local flush = bridge.screen.flushes
    bridge:request("nvim_command", { "redraw!" }, 5000)
    bridge:wait_until(5000, function()
      return bridge.screen.flushes > flush
    end)
    local visible = {}
    for _, window in ipairs(bridge.screen:snapshot("folded-message-headers").windows) do
      for _, row in ipairs(window.rows) do
        local text = {}
        for _, chunk in ipairs(row) do
          text[#text + 1] = chunk.text
        end
        visible[#visible + 1] = table.concat(text)
      end
    end
    local text = table.concat(visible, "\n")
    assert.is_truthy(text:find("Older question to summarize", 1, true))
    assert.is_truthy(text:find("Older agent answer", 1, true))
    exec([[
      local messages = view.message_presentation.messages
      local function row(index)
        return vim.fn.screenpos(view.thread_win, messages[index].first, 1).row
      end
      assert(row(2) - row(1) == 1, "Consecutive fold summaries must stay adjacent")
      assert(row(3) - row(2) == 2, "The expanded header needs exactly one blank row after the fold group")
    ]])
    exec([[
      vim.api.nvim_set_current_win(view.thread_win)
      -- Entering the conversation acknowledges its displayed incoming activity.
      local before = vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false)
      local first = view.message_presentation.messages[1].first
      vim.api.nvim_win_set_cursor(view.thread_win, { first, 0 })
      ui_key(view.thread_buf, "za")
      assert(vim.fn.foldclosed(first) == -1)
      ui_key(view.thread_buf, "zc")
      assert(vim.fn.foldclosed(first) == first)
      ui_key(view.thread_buf, "zR")
      assert(vim.fn.foldclosed(first) == -1)
      assert(vim.deep_equal(before, vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false)))
    ]])
  end)

  it("disposes popup chrome when its body buffer is wiped externally", function()
    exec([[
      _G.initial_windows = #vim.api.nvim_list_wins()
      require("commentry.inbox").new_thread()
      vim.cmd.stopinsert()
      vim.api.nvim_buf_delete(vim.api.nvim_get_current_buf(), { force = true })
    ]])
    assert.is_true(exec([[
      return vim.wait(500, function()
        return #vim.api.nvim_list_wins() == initial_windows
      end)
    ]]))
  end)

  it("keeps a composer on screen and removes all chrome after native closure", function()
    exec([[
      _G.initial_windows = #vim.api.nvim_list_wins()
      require("commentry.inbox").new_thread()
      vim.cmd.stopinsert()
      _G.editor = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(editor, 0, -1, false, { "Draft retained on resize" })
    ]])
    bridge:request("nvim_ui_try_resize", { 80, 16 }, 5000)
    bridge:wait_for_flush(5000)
    assert.is_true(exec([[
      local win = vim.api.nvim_get_current_win()
      local config = vim.api.nvim_win_get_config(win)
      assert(config.width <= 72 and config.height <= 10)
      assert(vim.api.nvim_buf_get_lines(editor, 0, 1, false)[1] == "Draft retained on resize")
      vim.api.nvim_win_close(win, true)
      return true
    ]]))
    assert.is_true(exec([[
      vim.wait(500, function() return not vim.api.nvim_buf_is_valid(editor) end)
      assert(not vim.api.nvim_buf_is_valid(editor))
      assert(#vim.api.nvim_list_wins() == initial_windows)
      return #assert(require("commentry.inbox.store").list(vim.fn.getcwd())) == 0
    ]]))
  end)
end)
