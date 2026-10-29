local function read_env(name, default)
  local value = vim.env[name]
  if type(value) ~= "string" or value == "" then
    return default
  end
  return value
end

local function read_env_number(name, default)
  local value = tonumber(read_env(name, ""))
  if type(value) ~= "number" or value <= 0 then
    return default
  end
  return math.floor(value)
end

local root = assert(vim.env.COMMENTRY_REPO_ROOT, "COMMENTRY_REPO_ROOT is required")
vim.opt.runtimepath:prepend(root)

local Bridge = require("commentry.dev.ui_bridge")
local cache = assert(vim.env.COMMENTRY_UI_CACHE, "COMMENTRY_UI_CACHE is required")
local cwd = assert(vim.env.COMMENTRY_UI_CWD, "COMMENTRY_UI_CWD is required")
local out_dir = read_env("COMMENTRY_UI_OUT_DIR", cwd)
local scenario = read_env("COMMENTRY_UI_SCENARIO", "inbox")
local columns = read_env_number("COMMENTRY_UI_COLUMNS", 220)
local lines = read_env_number("COMMENTRY_UI_LINES", 18)

local bridge = Bridge.Bridge.new({
  cmd = "nvim",
  args = {
    "--embed",
    "--clean",
    "-u",
    root .. "/scripts/ui-init.lua",
  },
  cwd = cwd,
  env = {
    COMMENTRY_REPO_ROOT = root,
    COMMENTRY_UI_CACHE = cache,
  },
  width = columns,
  height = lines,
})

local ok, err = xpcall(function()
  bridge:request("nvim_ui_attach", {
    columns,
    lines,
    {
      rgb = true,
      ext_linegrid = true,
      ext_multigrid = true,
    },
  }, 5000)

  bridge:wait_for_flush(5000)
  if scenario == "capture" then
    bridge:request("nvim_exec_lua", {
      [[
        local config = vim.fn.getcwd() .. "/capture.json"
        vim.fn.writefile({vim.json.encode({project=vim.fn.getcwd(), text="Error: found two matching excerpts.\nUnable to choose a destination.\nPlease narrow the selected range.", executable=vim.env.COMMENTRY_REPO_ROOT .. "/bin/commentry", directory=vim.fn.getcwd() .. "/inbox-data"})}, config)
        vim.env.COMMENTRY_CAPTURE_CONFIG = config
        dofile(vim.env.COMMENTRY_REPO_ROOT .. "/capture/composer.lua")
        vim.api.nvim_buf_set_lines(0,0,-1,false,{"Can we make this error more useful?", "", "Show both candidate locations so I can choose the right one."})
        return true
      ]], {},
    },5000)
    bridge:wait_for_flush(5000)
    local snapshot = bridge.screen:snapshot("rpc-capture")
    Bridge.write_snapshot_files(snapshot,bridge.screen,out_dir,"rpc-capture")
    return
  end
  if scenario == "inbox" then
    bridge:request("nvim_exec_lua", {
      [[
        vim.env.COMMENTRY_INBOX_DIR = vim.fn.getcwd() .. "/inbox-data"
        vim.cmd.edit("demo.lua")
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
          "local function request(url, retries)",
          "  for attempt = 1, retries do",
          "    local result = fetch(url)",
          "    if result.ok then return result end",
          "  end",
          "end",
        })
        local store = require("commentry.inbox.store")
        local capture = assert(require("commentry.inbox.source").capture(buf, 2, 4))
        capture.body = "Can we cap the total time spent retrying?"
        capture.title = "Cap total retry time"
        local id = assert(store.create(capture))
        assert(store.update(id, { kind = "reply", author = "Agent", body = "Added a shared deadline. Retries now stop after ten seconds." }))
        assert(store.update(id, {
          kind = "comparison",
          author = "Agent",
          label = "Shared retry deadline",
          before = "for attempt = 1, retries do\n  local result = fetch(url)\nend\n",
          after = "local deadline = clock() + 10\nfor attempt = 1, retries do\n  if clock() >= deadline then return nil end\n  local result = fetch(url)\nend\n",
        }))
        vim.api.nvim_buf_set_lines(buf, 1, 1, false, {
          "  local deadline = clock() + 10",
        })
        vim.api.nvim_buf_set_lines(buf, 3, 3, false, {
          '    if clock() >= deadline then return nil, "timeout" end',
        })
        assert(store.create({project = capture.project, title = "Explain this test failure", body = "Include both candidate locations in this error.", source = {kind = "text", lines = {"Found two matching excerpts.", "Unable to choose a destination."}}}))
        assert(store.create({project = capture.project, title = "A general project question", body = "Can we make the next milestone smaller?", source = {kind = "text", lines = {}, origin = "general"}}))
        local question = assert(store.create({project = capture.project, title = "Return errors at the retry deadline", author = "Codex", body = "The timeout branch returns nil without explaining why. The parser wrapper and tests also need review.", source = {kind = "text", lines = {"From our chat: retries share a ten second deadline."}, origin = "clipboard"}}))
        local location = assert(require("commentry.inbox.source").capture(buf, 3, 6))
        local excerpt_first = math.max(1, location.source.first - 1)
        location.source.lines = vim.list_slice(location.source.lines, excerpt_first, location.source.last + 1)
        location.source.excerpt_first = excerpt_first
        assert(store.update(question, {kind = "attach", label = "Retry implementation", source = location.source, author = "Codex"}))
        local example = assert(store.update(question, {kind = "comparison", label = "Timeout result before -> after the local fix", author = "Codex", before = 'request(url) -> nil\n', after = 'request(url) -> nil, "timeout"\n'}))
        assert(store.update(question, {kind = "comparison", label = "Implementation before -> after the local fix", author = "Codex", before = 'if clock() >= deadline then return nil end\n', after = 'if clock() >= deadline then return nil, "timeout" end\n'}))
        assert(store.update(question, {kind = "comparison", label = "Regression test for the timeout error", author = "Codex", before = 'assert.is_nil(request(url))\n', after = 'local result, err = request(url)\nassert.is_nil(result)\nassert.are.equal("timeout", err)\n'}))
        assert(store.update(question, {kind = "revise", title = "Timeouts fail without an explanation", author = "Codex", body = "When retries reach the deadline, callers receive nil with no reason. They cannot distinguish a timeout from another failure.\n\nThe local fix returns a timeout error. Please review the visible result beside this thread. Implementation and test evidence are folded below it.", primary_comparison = example.id}))
        assert(store.update(question, {kind = "reply", author = "You", body = "Will callers still receive partial results?"}))
        vim.api.nvim_buf_set_lines(buf, 0, 0, false, {"-- Requests share one deadline across all attempts."})
        _G.commentry_capture_view = require("commentry.inbox").open(nil, {thread = question})
        return true
      ]],
      {},
    }, 5000)
    bridge:wait_for_flush(5000)
    local snapshot = bridge.screen:snapshot("rpc-inbox")
    Bridge.write_snapshot_files(snapshot, bridge.screen, out_dir, "rpc-inbox")
    bridge:request("nvim_exec_lua", { [[
      local view = _G.commentry_capture_view
      vim.api.nvim_set_current_win(view.source_win)
      for row, line in ipairs(vim.api.nvim_buf_get_lines(view.source_buf, 0, -1, false)) do
        if line:find('if clock()', 1, true) then
          vim.api.nvim_win_set_cursor(view.source_win, {row, 0})
          vim.cmd('normal! zv')
          break
        end
      end
      vim.cmd('normal! Vj')
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(view.source_buf, 'x')) do
        if map.lhs == 'r' then map.callback(); break end
      end
      vim.cmd.stopinsert()
      vim.api.nvim_buf_set_lines(view.thread_buf, -2, -1, false, {'Could we make this timeout message clearer?'})
      vim.api.nvim_win_set_cursor(view.thread_win, {vim.api.nvim_buf_line_count(view.thread_buf), 0})
      vim.cmd('normal! zb')
      return true
    ]], {} }, 5000)
    bridge:wait_for_flush(5000)
    local reply = bridge.screen:snapshot("rpc-inbox-reply")
    Bridge.write_snapshot_files(reply, bridge.screen, out_dir, "rpc-inbox-reply")
    bridge:request("nvim_exec_lua", { [[
      local view = _G.commentry_capture_view
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(view.list_buf, "n")) do
        if map.lhs == "gf" then map.callback(); break end
      end
      return true
    ]], {} }, 5000)
    bridge:wait_for_flush(5000)
    local code = bridge.screen:snapshot("rpc-inbox-code")
    Bridge.write_snapshot_files(code, bridge.screen, out_dir, "rpc-inbox-code")
    return
  end
  bridge:request("nvim_exec_lua", { [[
    vim.env.COMMENTRY_INBOX_DIR = vim.fn.getcwd() .. "/inbox-data"
    vim.cmd("Commentry open")
    return true
  ]], {} }, 5000)

  bridge:wait_until(5000, function()
    local result = bridge:request("nvim_exec_lua", {
      [[
        local diffview = require("commentry.diffview")
        local view = diffview.get_current_view()
        return type(view) == "table" and view.ready == true
      ]],
      {},
    }, 5000)
    return result == true
  end)
  bridge:wait_for_flush(5000)

  bridge:wait_until(5000, function()
    local ok = bridge:request("nvim_exec_lua", {
      [[
        local diffview = require("commentry.diffview")
        local view = diffview.get_current_view()
        if type(view) ~= "table" then
          return false
        end
        local slot = view.cur_entry and view.cur_entry.layout.b
        if not slot or not slot.file or not slot.file.bufnr then return false end
        local wins = vim.fn.win_findbuf(slot.file.bufnr)
        if #wins == 0 then return false end
        vim.api.nvim_set_current_win(wins[1])
        local context = diffview.current_file_context()
        if not context then
          return false
        end
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        return true
      ]],
      {},
    }, 5000)
    return ok == true
  end)
  bridge:wait_for_flush(5000)

  if scenario == "popup" then
    bridge:request("nvim_input", { "mc" }, 2000)
    bridge:wait_until(5000, function()
      for _, window in pairs(bridge.screen.windows) do
        if window.kind == "float" and not window.hidden then
          return true
        end
      end
      return false
    end)
    local snapshot = bridge.screen:snapshot("rpc-comment-popup")
    Bridge.write_snapshot_files(snapshot, bridge.screen, out_dir, "rpc-comment-popup")
    return
  end

  if scenario == "diffview" then
    bridge:request("nvim_exec_lua", { [[
      local source_buf = vim.api.nvim_get_current_buf()
      vim.cmd("normal! Vj")
      local comment
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(source_buf, "x")) do
        if map.lhs == "mc" then comment = map.callback; break end
      end
      assert(comment, "Missing Diffview range mapping")()
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {"Can this name explain the changed value?", "", "This selection covers both the renamed value and the extra flag. Please keep those changes easy to understand together."})
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
        if map.lhs:lower() == "<c-s>" then map.callback(); break end
      end
      require("commentry.diffview").refresh()
      local context = assert(require("commentry.diffview").current_file_context())
      local threads = assert(require("commentry.inbox.store").list(context.project))
      assert(#threads == 1, "Expected one saved inbox thread")
      local ns = vim.api.nvim_create_namespace("commentry.inbox.locations")
      assert(#vim.api.nvim_buf_get_extmarks(context.bufnr, ns, 0, -1, {}) > 0, "Missing inbox marker")
      vim.cmd.redraw()
      return true

    ]], {} }, 5000)
    -- Drain scheduled buffer-enter redraws after the composer closes before
    -- recording the sign column. One earlier flush may still belong to it.
    local flushes = bridge.screen.flushes
    bridge:request("nvim_command", { "redraw!" }, 5000)
    bridge:wait_until(5000, function() return bridge.screen.flushes > flushes end)
    local snapshot = bridge.screen:snapshot("rpc-diffview-inbox")
    Bridge.write_snapshot_files(snapshot, bridge.screen, out_dir, "rpc-diffview-inbox")
    bridge:request("nvim_exec_lua", { [[
      require("commentry.inbox.locations").open_at_cursor()
      assert(vim.api.nvim_buf_get_name(0) == "commentry://inbox", "Thread did not open")
      return true
    ]], {} }, 5000)
    bridge:wait_for_flush(5000)
    local inbox = bridge.screen:snapshot("rpc-diffview-thread")
    Bridge.write_snapshot_files(inbox, bridge.screen, out_dir, "rpc-diffview-thread")
    return
  end

  error(("Unknown scenario: %s"):format(scenario))
end, debug.traceback)

bridge:close()

if not ok then
  error(err)
end
