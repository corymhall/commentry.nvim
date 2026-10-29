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

  it("keeps a failed popup save editable and supports normal-mode save and cancel", function()
    local thread = file({ "local value = 1" }, 1)
    vim.api.nvim_set_current_buf(buf)
    local Inbox = require("commentry.inbox")
    local function mapping(buffer, lhs)
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(buffer, "n")) do
        if map.lhs == lhs then
          return map.callback
        end
      end
      error("Missing popup mapping: " .. lhs)
    end
    Inbox.comment()
    vim.cmd.stopinsert()
    local popup = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(popup, 0, -1, false, { "Keep this draft", "across a failed save" })
    local original = Store.create
    Store.create = function()
      return nil, "Simulated unavailable backend"
    end
    local ok, err = pcall(mapping(popup, "<CR>"))
    Store.create = original
    assert.is_true(ok, tostring(err))
    assert.is_true(vim.api.nvim_buf_is_valid(popup))
    mapping(popup, "<CR>")()
    assert.is_false(vim.api.nvim_buf_is_valid(popup))
    local threads = assert(Store.list(thread.project))
    assert.are.same(2, #threads)
    for _, saved in ipairs(threads) do
      if saved.id ~= thread.id then
        assert.are.same("Keep this draft\nacross a failed save", assert(Store.get(saved.id)).messages[1].body)
      end
    end
    Inbox.comment()
    vim.cmd.stopinsert()
    popup = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(popup, 0, -1, false, { "Do not save" })
    mapping(popup, "<Esc>")()
    assert.is_false(vim.api.nvim_buf_is_valid(popup))
    assert.are.same(2, #assert(Store.list(thread.project)))
  end)

  it("quotes a visual source selection into an inline reply and saves before sending", function()
    local thread = file({ "local first = 1", "local second = 2", "return first + second" }, 1, 2)
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "local first = 3" })
    local view = require("commentry.inbox").open(nil, { project = root, thread = thread.id })
    vim.api.nvim_set_current_win(view.source_win)
    local rows = vim.api.nvim_buf_get_lines(view.source_buf, 0, -1, false)
    local first
    for index, line in ipairs(rows) do
      if line == "-local first = 1" then
        first = index
      end
    end
    assert.is_truthy(first)
    vim.api.nvim_win_set_cursor(view.source_win, { first, 0 })
    vim.cmd("normal! Vj")
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(view.source_buf, "x")) do
      if map.lhs == "r" then
        map.callback()
      end
    end
    vim.cmd.stopinsert()
    assert.are.same(view.thread_buf, vim.api.nvim_get_current_buf())
    vim.api.nvim_buf_set_lines(view.thread_buf, -2, -1, false, { "Can we combine these?" })
    vim.cmd.write()
    local saved = assert(Store.get(thread.id))
    assert.are.same(
      "> example.lua\n> -local first = 1\n> +local first = 3\n\nCan we combine these?",
      saved.messages[#saved.messages].body
    )
    assert.are.same(thread.source, saved.source)
    assert.are.same(0, #saved.queue)
    vim.cmd.write()
    assert.are.same(2, #assert(Store.get(thread.id)).messages)
    keys(view).s()
    saved = assert(Store.get(thread.id))
    assert.are.same(1, #saved.queue)
    assert.is_truthy(saved.queue[1].message:find("Can we combine these?", 1, true))
  end)

  it("retains inline drafts through refreshes switches closure and a failed save", function()
    local id, other = create("First question"), create("Second question")
    local Inbox = require("commentry.inbox")
    local view = Inbox.open(nil, { project = root, thread = id })
    keys(view).r()
    vim.cmd.stopinsert()
    vim.api.nvim_buf_set_lines(view.thread_buf, -2, -1, false, { "A draft reply", "with another line" })
    assert(Store.update(id, { kind = "reply", author = "Agent", body = "Arrived while drafting" }))
    keys(view).R()
    view = Inbox.open(nil, { project = root, thread = other })
    view = Inbox.open(nil, { project = root, thread = id })
    local before = vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false)
    assert.are.same({ "A draft reply", "with another line" }, { before[#before - 1], before[#before] })
    keys(view).q()
    view = Inbox.open(nil, { project = root, thread = id })
    assert.are.same(before, vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false))
    keys(view).r()
    vim.cmd.stopinsert()
    assert.is_true(assert(Store.get(id)).unread)
    local original = Store.update
    Store.update = function()
      return nil, "Simulated unavailable backend"
    end
    local ok, err = pcall(vim.cmd.write)
    Store.update = original
    assert.is_true(ok, tostring(err))
    assert.is_true(vim.bo[view.thread_buf].modified)
    assert.are.same(before, vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false))
    vim.cmd.write()
    local saved = assert(Store.get(id))
    assert.are.same("A draft reply\nwith another line", saved.messages[#saved.messages].body)
    assert.are.same(1, #assert(Store.get(other)).messages)
    assert.is_truthy(
      table
        .concat(vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false), "\n")
        :find("Arrived while drafting", 1, true)
    )
    assert.is_false(vim.bo[view.thread_buf].modified)
  end)

  it("refuses history edits and sending unsaved inline replies", function()
    local id = create("Immutable question")
    local view = require("commentry.inbox").open(nil, { project = root, thread = id })
    keys(view).r()
    vim.cmd.stopinsert()
    vim.api.nvim_buf_set_lines(view.thread_buf, -2, -1, false, { "Unsaved reply" })
    keys(view).s()
    assert.are.same(0, #assert(Store.get(id)).queue)
    local title = vim.api.nvim_buf_get_lines(view.thread_buf, 0, 1, false)
    vim.api.nvim_buf_set_lines(view.thread_buf, 0, 1, false, { "Rewritten history" })
    vim.cmd.write()
    assert.are.same(1, #assert(Store.get(id)).messages)
    assert.is_true(vim.bo[view.thread_buf].modified)
    vim.api.nvim_buf_set_lines(view.thread_buf, 0, 1, false, title)
    vim.cmd.write()
    assert.are.same("Unsaved reply", assert(Store.get(id)).messages[2].body)
  end)

  it("enriches copied text and navigates moved code without replacing its capture", function()
    local thread = file({ "local before = true", "local selected = 1", "return selected" }, 2)
    local id = create("Where is this handled?")
    local attachment =
      assert(Store.update(id, { kind = "attach", label = "Implementation", source = thread.source, author = "Agent" }))
    local enriched = assert(Store.get(id))
    assert.are.same({ "Selected output" }, enriched.source.lines)
    assert.is_true(enriched.unread)
    assert.are.same(attachment.id, enriched.attachments[1].id)
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "-- inserted above" })
    vim.api.nvim_set_current_buf(buf)
    local origin = vim.api.nvim_get_current_win()
    local view = require("commentry.inbox").open(nil, { project = root, thread = id })
    assert.are.same(id, view.threads[vim.api.nvim_win_get_cursor(view.list_win)[1]].id)
    keys(view).gf()
    assert.are.same(origin, vim.api.nvim_get_current_win())
    assert.are.same({ 3, 0 }, vim.api.nvim_win_get_cursor(0))
    local ns = vim.api.nvim_get_namespaces()["commentry.inbox.locations"]
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    assert.is_true(#marks > 0)
    assert.are.same(2, marks[#marks][2])
    local select = vim.ui.select
    vim.ui.select = function(items, _, callback)
      for _, item in ipairs(items) do
        if item.id == id then
          callback(item)
          return
        end
      end
    end
    local ok, err = pcall(require("commentry.inbox.locations").open_at_cursor)
    vim.ui.select = select
    assert.is_true(ok, err)
    assert.are.same(view.tab, vim.api.nvim_get_current_tabpage())
    assert.are.same(id, view.threads[vim.api.nvim_win_get_cursor(view.list_win)[1]].id)
    require("commentry.inbox").open(nil, { project = root, thread = thread.id })
    local previews = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
      if mark[4].virt_text then
        previews[#previews + 1] = mark[4].virt_text[1][1]
      end
    end
    assert.are.same({ "  You: Explain this code" }, previews)
    vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "local replacement = 2" })
    local located = Source.with_location(assert(Store.get(id)))
    local target, err = Source.locate(located)
    assert.is_nil(target)
    assert.matches("Outdated", err)
    require("commentry.inbox.locations").set({}, nil)
  end)

  it("finds uniquely moved code and refuses ambiguous or unavailable destinations", function()
    local thread = file({ "start", "unique code", "end" }, 2)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "start", "end", "", "unique code" })
    assert.are.same(4, assert(Source.locate(thread)).first)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "start", "replacement", "end", "unique code", "unique code" })
    assert.is_nil(Source.locate(thread))
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.delete(root .. "/example.lua")
    assert.is_nil(Source.locate(thread))
  end)

  it("reviews comparisons and code locations together and navigates the section under the cursor", function()
    local thread = file({ "before", "selected", "after" }, 2)
    assert(
      Store.update(thread.id, { kind = "attach", label = "Implementation", source = thread.source, author = "Agent" })
    )
    local other_source =
      { kind = "file", path = "other.lua", first = 2, last = 2, lines = { "first", "other code", "last" } }
    vim.fn.writefile(other_source.lines, root .. "/other.lua")
    assert(Store.update(thread.id, { kind = "attach", label = "Caller", source = other_source, author = "Agent" }))
    assert(
      Store.update(
        thread.id,
        { kind = "comparison", label = "Suggested fix", before = "selected\n", after = "updated\n", author = "Agent" }
      )
    )
    vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "updated" })
    local view = require("commentry.inbox").open(nil, { project = root, thread = thread.id })
    local original, caller, implementation
    for _, section in ipairs(view.source_sections) do
      if section.id == "original" then
        original = section
      end
      if section.source and section.source.path == "other.lua" then
        caller = section
      end
      if section.source and section.id ~= "original" and section.source.path == "example.lua" then
        implementation = section
      end
    end
    assert.matches("Saved comparison", view.source_sections[1].title)
    assert.matches("Changed locally", implementation.title)
    assert.matches("Current code", caller.title)
    vim.api.nvim_set_current_win(view.source_win)
    vim.api.nvim_win_set_cursor(view.source_win, { 1, 0 })
    keys(view).gf()
    assert.are.same(view.source_win, vim.api.nvim_get_current_win())
    assert.are.same(original.first, vim.fn.foldclosed(original.first))
    vim.api.nvim_win_set_cursor(view.source_win, { original.first, 0 })
    vim.cmd("normal! zo")
    keys(view).e()
    original = view.source_sections[#view.source_sections]
    assert.are.same(-1, vim.fn.foldclosed(original.first))
    local select = vim.ui.select
    vim.ui.select = function(items, _, callback)
      for _, item in ipairs(items) do
        if item.source and item.source.path == "other.lua" then
          callback(item)
          return
        end
      end
    end
    local ok, err = pcall(keys(view).gl)
    vim.ui.select = select
    assert.is_true(ok, tostring(err))
    keys(view).gf()
    local other_buf = vim.api.nvim_get_current_buf()
    assert.are.same(root .. "/other.lua", vim.api.nvim_buf_get_name(other_buf))
    assert.are.same(2, vim.api.nvim_win_get_cursor(0)[1])
    require("commentry.inbox.locations").open_at_cursor()
    assert.are.same(view.tab, vim.api.nvim_get_current_tabpage())
    vim.api.nvim_set_current_win(view.source_win)
    for _, section in ipairs(view.source_sections) do
      if section.source and section.source.path == "example.lua" and section.id ~= "original" then
        vim.api.nvim_win_set_cursor(view.source_win, { section.first, 0 })
        break
      end
    end
    keys(view).gf()
    assert.are.same(buf, vim.api.nvim_get_current_buf())
    assert.are.same(2, vim.api.nvim_win_get_cursor(0)[1])
    require("commentry.inbox.locations").open_at_cursor()
    assert.are.same(view.tab, vim.api.nvim_get_current_tabpage())
    assert.are.same("selected", assert(Store.get(thread.id)).source.lines[2])
    vim.api.nvim_buf_delete(other_buf, { force = true })
  end)

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
    assert.is_nil(plain.l)
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
    local rows = table.concat(vim.api.nvim_buf_get_lines(view.source_buf, 0, -1, false), "\n")
    assert.is_truthy(rows:find("Focused refactor", 1, true))
    assert.is_truthy(rows:find("Agent", 1, true))
    assert.is_true(assert(Store.get(id)).unread)
    keys(view)["<CR>"]()
    assert.is_false(assert(Store.get(id)).unread)
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

  it("sends new project comments across filters without replaying answered threads", function()
    local ids = {}
    for index = 1, 5 do
      ids[index] = create("Question " .. index)
    end
    for index = 1, 2 do
      assert(Store.enqueue(ids[index]))
      local claim = assert(Store.claim(root, "Agent"))
      assert(
        Store.update(ids[index], { kind = "finish", claim_ids = { claim.claim_id }, body = "Answer", author = "Agent" })
      )
    end
    assert(Store.update(ids[2], { kind = "reply", body = "A follow-up" }))
    local cancelled = assert(Store.enqueue(ids[3]))
    assert(Store.update(ids[3], { kind = "cancel", queue_id = cancelled.id, pending_only = true }))
    assert(Store.update(ids[4], { kind = "resolve", resolved = true }))
    local failed = create("Uncertain delivery")
    assert(Store.enqueue(failed))
    local failed_claim = assert(Store.claim(root, "Agent"))
    assert(Store.update(failed, { kind = "fail", claim_id = failed_claim.claim_id, body = "Acceptance unknown" }))
    assert(Store.enqueue(ids[5]))
    local other = create("Another project", root .. "/other")
    local agent_only = assert(Store.create({ project = root, body = "Agent note", author = "Agent" }))
    local view = require("commentry.inbox").open("unread", { project = root })
    local Util = require("commentry.util")
    local original, message = Util.info, nil
    local original_warn = Util.warn
    Util.info = function(value)
      message = value
    end
    Util.warn = Util.info
    local ok, err = pcall(function()
      keys(view).gs()
      assert.matches("3 queued, not delivered", message)
      assert.matches("Press S in the inbox", message)
      assert.are.same(1, #assert(Store.get(ids[1])).queue)
      assert.are.same(2, #assert(Store.get(ids[2])).queue)
      assert.are.same(2, #assert(Store.get(ids[3])).queue)
      assert.are.same(0, #assert(Store.get(ids[4])).queue)
      assert.are.same(1, #assert(Store.get(ids[5])).queue)
      assert.are.same(0, #assert(Store.get(other)).queue)
      assert.are.same(0, #assert(Store.get(agent_only)).queue)
      assert.are.same("failed", assert(Store.get(failed)).queue[1].status)
      -- A repeated batch may deliver pending work but never adds copies.
      keys(view).gs()
      assert.are.same(2, #assert(Store.get(ids[2])).queue)
      assert.are.same(2, #assert(Store.get(ids[3])).queue)
      assert.are.same(1, #assert(Store.get(ids[5])).queue)
      for _ = 1, 3 do
        local pending = assert(Store.claim(root, "Agent"))
        assert(
          Store.update(
            pending.thread,
            { kind = "finish", claim_ids = { pending.claim_id }, body = "Done", author = "Agent" }
          )
        )
      end
      keys(view).gs()
      assert.are.same("Nothing new to send. There are no new comments.", message)
    end)
    Util.info = original
    Util.warn = original_warn
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
    local section = Source.sections(threads[1])[1]
    local comparison = section.comparison
    assert.is_truthy(table.concat(comparison.lines, "\n"):find("+new", 1, true))
    assert.is_truthy(section.detail:find("Agent", 1, true))
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
    local sections = Source.sections(thread)
    assert.are.same(1, #sections)
    assert.matches("Saved snapshot", sections[1].title)
    assert.matches("File unavailable", sections[1].detail)
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
