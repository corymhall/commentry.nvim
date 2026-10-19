---@module 'luassert'
local Source = require("commentry.inbox.source")
local Store = require("commentry.inbox.store")

describe("universal inbox", function()
  local root, directory, previous_directory, buf, original_columns

  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    root = vim.uv.fs_realpath(root)
    directory = root .. "/journal"
    previous_directory = vim.env.COMMENTRY_INBOX_DIR
    original_columns = vim.o.columns
    vim.env.COMMENTRY_INBOX_DIR = directory
  end)

  after_each(function()
    vim.cmd.stopinsert()
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      local found = false
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == "commentry://inbox" then
          found = true
        end
      end
      if found then
        vim.api.nvim_set_current_tabpage(tab)
        vim.cmd.tabclose()
      end
    end
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    buf = nil
    vim.env.COMMENTRY_INBOX_DIR = previous_directory
    vim.o.columns = original_columns
    vim.fn.delete(root, "rf")
  end)

  local function create(body, project)
    return assert(Store.create({
      project = project or root,
      body = body or "Inspect this",
      source = { kind = "text", lines = { "Selected output" } },
    }))
  end

  local function file(lines, first, last)
    vim.fn.writefile(lines, root .. "/example.lua")
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, root .. "/example.lua")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local capture = assert(Source.capture(buf, first, last or first))
    capture.body = "Explain this code"
    local id = assert(Store.create(capture))
    return assert(Store.get(id))
  end

  local function keys(view)
    local result = {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(view.list_buf, "n")) do
      result[map.lhs] = map.callback
    end
    return result
  end

  it("reflows on resize and navigates panels without changing plain text motions", function()
    create()
    vim.o.columns = 200
    local view = require("commentry.inbox").open("all")
    local rows =
      { vim.api.nvim_win_get_position(view.source_win)[1], vim.api.nvim_win_get_position(view.thread_win)[1] }
    assert.are.same(rows[1], rows[2])
    local plain = {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(view.list_buf, "n")) do
      plain[map.lhs] = true
    end
    assert.is_nil(plain.h)
    assert.is_nil(plain.j)
    local control = keys(view)["<C-L>"] or keys(view)["<C-l>"]
    control()
    assert.are.same(view.source_win, vim.api.nvim_get_current_win())
    vim.o.columns = 100
    vim.api.nvim_exec_autocmds("VimResized", {})
    assert.are.same(
      vim.api.nvim_win_get_position(view.source_win)[2],
      vim.api.nvim_win_get_position(view.thread_win)[2]
    )
    assert.is_true(vim.api.nvim_buf_is_valid(view.source_buf))
    assert.is_true(vim.api.nvim_buf_is_valid(view.thread_buf))
  end)

  it("opens an external project's inbox without changing the editor directory", function()
    local cwd = vim.fn.getcwd()
    local id = create("From the agent project")
    create("Another project", root .. "/other")
    local view = require("commentry.inbox").open(nil, { project = root })
    assert.are.same(root, view.project)
    assert.are.same(1, #view.threads)
    assert.are.same(id, view.threads[1].id)
    assert.are.same(cwd, vim.fn.getcwd())
  end)

  it("creates standalone threads inside the inbox and can filter new activity", function()
    local view = require("commentry.inbox").open("all")
    keys(view).n()
    local editor = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(editor, 0, -1, false, { "A standalone question", "No selection or clipboard required." })
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(editor, "n")) do
      if map.lhs == "<C-S>" or map.lhs == "<C-s>" then
        map.callback()
      end
    end
    local threads = assert(Store.list())
    assert.are.same(1, #threads)
    assert.are.same("general", threads[1].source.origin)
    assert.are.same({}, threads[1].source.lines)
    assert(Store.update(threads[1].id, { kind = "reply", author = "Agent", body = "New response" }))
    view = require("commentry.inbox").open("unread")
    -- The standalone creation uses the current project, not the temporary fixture root.
    assert.are.same(1, #view.threads)
    assert.is_true(view.threads[1].unread)
    assert.is_truthy(
      table.concat(vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false), "\n"):find("New response", 1, true)
    )
  end)

  it("reopens a complete inbox after a native command closes any owned panel", function()
    create()
    local Inbox = require("commentry.inbox")
    local view = Inbox.open("all")
    for _, panel in ipairs({ "source_win", "thread_win", "list_win" }) do
      local old = view
      vim.api.nvim_set_current_win(view[panel])
      vim.cmd.quit()
      view = Inbox.open("all")
      assert.is_false(vim.api.nvim_tabpage_is_valid(old.tab))
      assert.is_true(vim.api.nvim_win_is_valid(view.list_win))
      assert.is_true(vim.api.nvim_win_is_valid(view.source_win))
      assert.is_true(vim.api.nvim_win_is_valid(view.thread_win))
      assert.are.same(1, #view.threads)
      vim.wait(20, function()
        return false
      end)
      assert.is_true(vim.api.nvim_tabpage_is_valid(view.tab))
    end
  end)

  it("shows an agent comparison attachment before acknowledging its incoming activity", function()
    local id = create()
    assert(Store.update(id, {
      kind = "comparison",
      author = "Agent",
      before = "original code\n",
      after = "replacement code\n",
      label = "Focused refactor",
    }))
    local view = require("commentry.inbox").open("all")
    local rows = table.concat(vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false), "\n")
    assert.is_truthy(rows:find("Focused refactor", 1, true))
    assert.is_truthy(rows:find("Agent", 1, true))
    assert.is_true(assert(Store.get(id)).unread)
    keys(view)["<CR>"]()
    assert.is_false(assert(Store.get(id)).unread)
    local original_select = vim.ui.select
    vim.ui.select = function(_, _, callback)
      callback("agent")
    end
    local ok, err = pcall(keys(view).c)
    vim.ui.select = original_select
    assert.is_true(ok, tostring(err))
    local diff = table.concat(vim.api.nvim_buf_get_lines(view.source_buf, 0, -1, false), "\n")
    assert.is_truthy(diff:find("replacement code", 1, true))
  end)

  it("does not mark previewed threads read until their conversation is opened", function()
    local id = create()
    assert(Store.update(id, { kind = "reply", author = "Agent", body = "Incoming" }))
    local view = require("commentry.inbox").open("all")
    assert.is_true(assert(Store.get(id)).unread)
    keys(view)["<CR>"]()
    assert.is_false(assert(Store.get(id)).unread)
  end)

  it("scopes standalone comments to the current project outside an existing inbox tab", function()
    local tab, cwd = vim.api.nvim_get_current_tabpage(), vim.fn.getcwd()
    vim.cmd("lcd " .. vim.fn.fnameescape(root))
    local ok, view = pcall(require("commentry.inbox").open)
    vim.api.nvim_set_current_tabpage(tab)
    vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
    assert.is_true(ok, tostring(view))
    require("commentry.inbox").new_thread()
    local editor = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(editor, 0, -1, false, { "Question for the current project" })
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(editor, "n")) do
      if map.lhs == "<C-S>" or map.lhs == "<C-s>" then
        map.callback()
      end
    end
    local threads = assert(Store.list(Source.project(cwd)))
    assert.are.same(1, #threads)
    assert.are.same("Question for the current project", threads[1].messages[1].body)
    assert.are.same(0, #assert(Store.list(root)))
  end)

  it("refreshes a reply committed while the previous thread list was loading", function()
    local id = create()
    local original_list = Store.list
    Store.list = function(project, opts)
      local threads, err = original_list(project, opts)
      assert(Store.update(id, { kind = "reply", author = "Agent", body = "Arrived during refresh" }))
      return threads, err
    end
    local ok, view = pcall(require("commentry.inbox").open, "all")
    Store.list = original_list
    assert.is_true(ok, tostring(view))
    assert.is_true(vim.wait(3000, function()
      local rows = vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false)
      return table.concat(rows, "\n"):find("Arrived during refresh", 1, true) ~= nil
    end, 50))
  end)

  it("persists queued requests and only lets one external worker claim each request", function()
    local id = create()
    local Agent = require("commentry.inbox.agent")
    assert(Agent.send(id, "queue"))
    assert(Agent.send(id, "queue"))
    assert.are.same(1, #assert(Store.get(id)).queue)
    local jobs = {}
    for i = 1, 4 do
      jobs[i] = vim.system({ vim.fn.getcwd() .. "/scripts/commentry-inbox" }, {
        env = { COMMENTRY_INBOX_DIR = directory },
        text = true,
        stdin = vim.json.encode({ action = "claim", project = root, author = "Worker " .. i }),
      })
    end
    local claims = {}
    for _, job in ipairs(jobs) do
      local result = job:wait(10000)
      local response = vim.json.decode(result.stdout)
      if response.ok and response.result.claim_id then
        claims[#claims + 1] = response.result
      end
    end
    assert.are.same(1, #claims)
    assert.are.same(id, claims[1].thread)
    assert.is_truthy(claims[1].message:find("Selected output", 1, true))
    assert.is_nil(Store.update(id, { kind = "complete", claim_id = "wrong" }))
    assert(Store.update(id, { kind = "complete", claim_id = claims[1].claim_id }))
    assert.are.same("complete", assert(Store.get(id)).queue[1].status)
    assert.is_false(assert(Store.get(id)).resolved)
    assert(Agent.send(id, "queue"))
    local second = assert(Store.claim(root, "Agent"))
    assert.is_nil(Store.update(id, { kind = "cancel", queue_id = second.queue_id, pending_only = true }))
    assert(Store.update(id, { kind = "cancel", queue_id = second.queue_id }))
    assert.is_nil(Store.update(id, { kind = "complete", claim_id = second.claim_id }))
  end)

  it("explains skipped sends and allows sending after a new reply", function()
    local id = create()
    assert(Store.enqueue(id))
    assert(Store.claim(root, "Agent"))
    local view = require("commentry.inbox").open("all")
    local Util = require("commentry.util")
    local original, messages = Util.info, {}
    Util.info = function(message)
      messages[#messages + 1] = message
    end
    local ok, err = pcall(function()
      keys(view).s()
      assert.are.same("Nothing new to send. There are no new messages.", messages[#messages])
      assert.are.same(1, #assert(Store.get(id)).queue)
      assert(Store.update(id, { kind = "reply", body = "One more thing to check" }))
      keys(view).s()
      assert.are.same("Saved for delivery", messages[#messages])
      assert.are.same(2, #assert(Store.get(id)).queue)
    end)
    Util.info = original
    assert.is_true(ok, tostring(err))
  end)

  it("reports when attaching or delivering pending requests sends nothing", function()
    local Agent = require("commentry.inbox.agent")
    local Util = require("commentry.util")
    local original_command, original_select, original_info = Store.command, vim.ui.select, Util.info
    local messages, sent = {}, 0
    local agent = { id = "existing", harness = "codex", name = "Existing Codex", rex_block = "block" }
    Store.command = function(args)
      local action = args[4]
      if action == "list" then
        return { sessions = { agent } }
      elseif action == "status" then
        return { state = "working", agent = agent }
      elseif action == "attach" or action == "dispatch" then
        return { sent = sent }
      end
      error("Unexpected action: " .. action)
    end
    vim.ui.select = function(items, _, callback)
      callback(type(items[1]) == "table" and items[1] or "Deliver pending requests")
    end
    Util.info = function(message)
      messages[#messages + 1] = message
    end
    local ok, err = pcall(function()
      Agent.choose(root)
      assert.are.same(
        "Nothing new to send. There are no pending requests. Attached to codex / Existing Codex",
        messages[#messages]
      )
      Agent.controls(root)
      assert.are.same("Nothing new to send. There are no pending requests.", messages[#messages])
      sent = 2
      Agent.choose(root)
      assert.are.same("Sent 2 request(s). Attached to codex / Existing Codex", messages[#messages])
    end)
    Store.command, vim.ui.select, Util.info = original_command, original_select, original_info
    assert.is_true(ok, tostring(err))
  end)

  it("shows multiline worker failures without breaking the conversation", function()
    local id = create()
    assert(Store.enqueue(id))
    local claim = assert(Store.claim(root, "worker"))
    assert(
      Store.update(id, { kind = "fail", claim_id = claim.claim_id, body = "Provider unavailable\nTry again later" })
    )
    local view = require("commentry.inbox").open("all")
    local contents = table.concat(vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false), "\n")
    assert.is_truthy(contents:find("Provider unavailable\nTry again later", 1, true))
    assert.are.same("failed", assert(Store.get(id)).queue[1].status)
  end)

  it("keeps queued requests pending when no existing session is selected", function()
    local id = create()
    local Agent = require("commentry.inbox.agent")
    assert(Agent.send(id, "queue"))
    local value, err = Agent.send(id, "steer")
    assert.is_nil(value)
    assert.is_truthy(err:find("no project agent", 1, true))
    local thread = assert(Store.get(id))
    assert.are.same(1, #thread.queue)
    assert.are.same("pending", thread.queue[1].status)
  end)

  it("preserves independent projects, conversation history and the original capture", function()
    local id = create()
    create("Other project", root .. "/other")
    assert(Store.update(id, { kind = "reply", body = "Fixed", author = "Agent" }))
    assert(Store.update(id, { kind = "resolve", resolved = true }))
    assert(
      Store.update(id, { kind = "comparison", before = "old\n", after = "new\n", label = "Refactor", author = "Agent" })
    )
    local threads = assert(Store.list(root))
    assert.are.same(1, #threads)
    assert.are.same(id, threads[1].id)
    assert.are.same({ "Selected output" }, threads[1].source.lines)
    assert.are.same(2, #threads[1].messages)
    assert.is_true(threads[1].resolved)
    local comparison = assert(Source.compare(threads[1], "agent"))
    assert.is_truthy(table.concat(comparison.lines, "\n"):find("+new", 1, true))
    assert.is_truthy(comparison.label:find("Agent", 1, true))
  end)

  it("rejects invalid external writes without poisoning existing threads", function()
    local id = create()
    local event = Store.update(id, { kind = "reply", author = "Agent\nInjected heading", body = "Reply" })
    assert.is_nil(event)
    local invalid = Store.create({
      project = root,
      body = "Invalid file metadata",
      source = { kind = "file", path = "../outside.lua", first = 1, last = 1, lines = { "code" } },
    })
    assert.is_nil(invalid)
    assert.are.same(1, #assert(Store.get(id)).messages)
    local result = vim
      .system({ vim.fn.getcwd() .. "/scripts/commentry-inbox" }, {
        stdin = '{"action":"reply","thread":"missing","body":"Reply"}',
        text = true,
      })
      :wait(10000)
    assert.are.same(1, result.code)
    assert.is_false(vim.json.decode(result.stdout).ok)
  end)

  it("captures unsaved buffer text and ignores unrelated edits above the selection", function()
    local contents = {}
    for i = 1, 30 do
      contents[i] = "line " .. i
    end
    local thread = file(contents, 20)
    vim.api.nvim_buf_set_lines(buf, 19, 20, false, { "unsaved change" })
    local capture = assert(Source.capture(buf, 20, 20))
    assert.are.same("unsaved change", capture.source.lines[20])
    vim.api.nvim_buf_set_lines(buf, 19, 20, false, { "line 20" })
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "unrelated insertion" })
    local comparison = assert(Source.compare(thread, "since"))
    assert.is_false(comparison.outdated)
    assert.are.same("line 16", comparison.lines[1])
    assert.is_nil(table.concat(comparison.lines, "\n"):find("unrelated insertion", 1, true))
  end)

  it("includes a replacement longer than the captured region and keeps outdated threads visible", function()
    local thread = file({ "old" }, 1)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "new", "more", "last replacement line" })
    local comparison = assert(Source.compare(thread, "since"))
    assert.is_true(comparison.outdated)
    assert.is_truthy(table.concat(comparison.lines, "\n"):find("+last replacement line", 1, true))
    local view = require("commentry.inbox").open("all")
    local transcript = table.concat(vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false), "\n")
    assert.is_truthy(transcript:find("Outdated", 1, true))
    assert.are.same(1, #view.threads)
  end)

  it("retains the excerpt when the file disappears", function()
    local thread = file({ "keep this original", "context" }, 1)
    vim.api.nvim_buf_delete(buf, { force = true })
    buf = nil
    vim.fn.delete(root .. "/example.lua")
    local comparison = assert(Source.compare(thread, "since"))
    assert.is_true(comparison.outdated)
    assert.are.same({ "keep this original", "context" }, comparison.lines)
  end)

  it("fails visibly when the SQLite database is corrupt", function()
    local id = create()
    assert.are.same(id, assert(Store.list(root))[1].id)
    vim.fn.writefile({ "not a SQLite database" }, directory .. "/inbox.sqlite3")
    local threads, err = Store.list(root)
    assert.is_nil(threads)
    assert.is_truthy(err:find("database", 1, true))
  end)

  it("does not lose replies from simultaneous external agent processes", function()
    local id = create()
    local cli = vim.fn.getcwd() .. "/scripts/commentry-inbox"
    local jobs = {}
    for i = 1, 4 do
      jobs[i] = vim.system({ cli }, {
        env = { COMMENTRY_INBOX_DIR = directory },
        stdin = vim.json.encode({ action = "reply", thread = id, body = "Reply " .. i, author = "Agent " .. i }),
        text = true,
      })
    end
    for _, job in ipairs(jobs) do
      local result = job:wait(10000)
      assert.are.same(0, result.code, result.stderr)
      assert.is_true(vim.json.decode(result.stdout).ok)
    end
    local thread = assert(Store.get(id))
    assert.are.same(5, #thread.messages)
    local authors = {}
    for _, message in ipairs(thread.messages) do
      authors[message.author] = true
    end
    for i = 1, 4 do
      assert.is_true(authors["Agent " .. i])
    end
  end)

  it("updates source and conversation together when moving between threads", function()
    create("First conversation")
    assert(Store.create({
      project = root,
      body = "Second conversation",
      source = { kind = "text", lines = { "Second captured excerpt" } },
    }))
    local view = require("commentry.inbox").open("all")
    vim.api.nvim_win_set_cursor(view.list_win, { 2, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = view.list_buf })
    local transcript = table.concat(vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false), "\n")
    assert.is_truthy(transcript:find("Second conversation", 1, true))
    local source = table.concat(vim.api.nvim_buf_get_lines(view.source_buf, 0, -1, false), "\n")
    assert.is_truthy(source:find("Second captured excerpt", 1, true))
  end)

  it("expands real diff context and keeps provenance accessible through inspect", function()
    local contents = {}
    for i = 1, 40 do
      contents[i] = "line " .. i
    end
    local thread = file(contents, 20)
    vim.api.nvim_buf_set_lines(buf, 19, 20, false, { "changed code" })
    local view = require("commentry.inbox").open("all")
    local function content(buffer)
      return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
    end
    assert.is_truthy(content(view.source_buf):find("changed code", 1, true))
    assert.is_nil(content(view.source_buf):find("line 4\n", 1, true))
    local maps = {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(view.list_buf, "n")) do
      maps[map.lhs] = map.callback
    end
    maps.e()
    assert.is_truthy(content(view.source_buf):find("line 4\n", 1, true))
    maps.i()
    local popup = vim.api.nvim_get_current_win()
    assert.is_truthy(content(vim.api.nvim_get_current_buf()):find(thread.id, 1, true))
    vim.api.nvim_win_close(popup, true)
  end)
end)
