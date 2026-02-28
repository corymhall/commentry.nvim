---@module 'luassert'

local Payload = require("commentry.codex.payload")

local function load_fixture(name)
  local path = ("tests/fixtures/%s"):format(name)
  local lines = vim.fn.readfile(path)
  return vim.json.decode(table.concat(lines, "\n"))
end

local function load_comments_with_store(stubs)
  local original_store = package.loaded["commentry.store"]
  local original_diffview = package.loaded["commentry.diffview"]
  local original_comments = package.loaded["commentry.comments"]

  package.loaded["commentry.store"] = stubs.store
  package.loaded["commentry.diffview"] = stubs.diffview
  package.loaded["commentry.comments"] = nil

  local comments = require("commentry.comments")

  package.loaded["commentry.store"] = original_store
  package.loaded["commentry.diffview"] = original_diffview
  package.loaded["commentry.comments"] = original_comments

  return comments
end

local function load_send_with_stubs(stubs)
  local original_config = package.loaded["commentry.config"]
  local original_diffview = package.loaded["commentry.diffview"]
  local original_comments = package.loaded["commentry.comments"]
  local original_payload = package.loaded["commentry.codex.payload"]
  local original_adapter = package.loaded["commentry.codex.adapter"]
  local original_sidekick = package.loaded["commentry.codex.adapters.sidekick"]
  local original_sidekick_preload = package.preload["commentry.codex.adapters.sidekick"]
  local original_send = package.loaded["commentry.codex.send"]

  package.loaded["commentry.config"] = stubs.config
  package.loaded["commentry.diffview"] = stubs.diffview
  package.loaded["commentry.comments"] = stubs.comments
  package.loaded["commentry.codex.payload"] = stubs.payload
  package.loaded["commentry.codex.adapter"] = stubs.adapter
  package.loaded["commentry.codex.adapters.sidekick"] = stubs.sidekick
  package.preload["commentry.codex.adapters.sidekick"] = function()
    return stubs.sidekick
  end
  package.loaded["commentry.codex.send"] = nil

  local send = require("commentry.codex.send")

  package.loaded["commentry.config"] = original_config
  package.loaded["commentry.diffview"] = original_diffview
  package.loaded["commentry.comments"] = original_comments
  package.loaded["commentry.codex.payload"] = original_payload
  package.loaded["commentry.codex.adapter"] = original_adapter
  package.preload["commentry.codex.adapters.sidekick"] = original_sidekick_preload
  package.loaded["commentry.codex.send"] = original_send

  return send
end

local function is_absolute_path(value)
  if type(value) ~= "string" or value == "" then
    return false
  end
  if value:sub(1, 1) == "/" then
    return true
  end
  if value:match("^%a:[/\\]") then
    return true
  end
  return false
end

local ROOT_KEYS = {
  root = true,
  repo_root = true,
  project_root = true,
  git_root = true,
}

local function assert_no_absolute_paths(value, key)
  if type(value) == "string" then
    if ROOT_KEYS[key] then
      return
    end
    assert.is_false(is_absolute_path(value))
    return
  end
  if type(value) ~= "table" then
    return
  end
  for child_key, entry in pairs(value) do
    assert_no_absolute_paths(entry, child_key)
  end
end

describe("commentry.codex.payload", function()
  it("builds payload with required top-level sections", function()
    local payload = Payload.build_payload({ context_id = "ctx-1" }, {
      review_meta = { mode = "working_tree" },
      items = { { id = "c1" } },
      provenance = { root = "/tmp/project" },
    })

    assert.are.same("ctx-1", payload.context.context_id)
    assert.are.same("working_tree", payload.review_meta.mode)
    assert.are.same("c1", payload.items[1].id)
    assert.are.same("/tmp/project", payload.provenance.root)
  end)

  it("normalizes provenance safely with table-driven cases", function()
    local cases = {
      {
        name = "normalizes in-repo absolute paths",
        context = { context_id = "ctx-1" },
        provenance = {
          root = "/Users/chall/gt/commentry/crew/fiddler",
          files = {
            "/Users/chall/gt/commentry/crew/fiddler/lua/commentry/commands.lua",
          },
        },
        expected_root = "/Users/chall/gt/commentry/crew/fiddler",
        expected_files = { "lua/commentry/commands.lua" },
      },
      {
        name = "drops absolute paths outside repo root",
        context = { context_id = "ctx-1" },
        provenance = {
          root = "/Users/chall/gt/commentry/crew/fiddler",
          files = {
            "/tmp/external.lua",
            "/Users/chall/gt/commentry/crew/fiddler/lua/commentry/commands.lua",
          },
        },
        expected_root = "/Users/chall/gt/commentry/crew/fiddler",
        expected_files = { "lua/commentry/commands.lua" },
      },
      {
        name = "drops absolute paths when root is unknown",
        context = { context_id = "ctx-1" },
        provenance = {
          files = {
            "/tmp/external.lua",
            "lua/commentry/commands.lua",
          },
        },
        expected_root = nil,
        expected_files = { "lua/commentry/commands.lua" },
      },
    }

    for _, case in ipairs(cases) do
      local payload = Payload.build_payload(case.context, {
        provenance = case.provenance,
      })
      assert.are.same(case.expected_root, payload.provenance.root, case.name)
      assert.are.same(case.expected_files, payload.provenance.files, case.name)
    end
  end)

  it("filters and projects active items with table-driven cases", function()
    local cases = {
      {
        name = "filters unresolved, stale and invalid comments",
        items = {
          { id = "inactive-unresolved", status = "unresolved", body = "a" },
          { id = "inactive-stale", stale = true, body = "b" },
          { id = "inactive-invalid", invalid = true, body = "c" },
          { id = "active-1", body = "kept one", comment_type = "suggestion" },
          { id = "active-2", body = "kept two" },
        },
        expected_ids = { "active-1", "active-2" },
      },
      {
        name = "orders deterministically by path and line metadata",
        items = {
          { id = "z-last", file_path = "z.lua", line_number = 1, body = "z" },
          { id = "a-second", file_path = "a.lua", line_number = 2, body = "a2" },
          { id = "a-first", file_path = "a.lua", line_number = 1, body = "a1" },
        },
        expected_ids = { "a-first", "a-second", "z-last" },
      },
    }

    for _, case in ipairs(cases) do
      local projected = Payload.extract_active_items(case.items)
      local ids = {}
      for _, item in ipairs(projected) do
        ids[#ids + 1] = item.id
      end
      assert.are.same(case.expected_ids, ids, case.name)
    end
  end)

  it("serializes deterministically with stable ordering", function()
    local context = { context_id = "ctx-1", revisions = { "HEAD~1..HEAD" } }
    local opts = {
      review_meta = { mode = "commit_range", why = "determinism" },
      items = {
        { id = "c2", file_path = "b.lua", line_number = 2, body = "second", created_at = "2026-01-02" },
        { id = "c1", file_path = "a.lua", line_number = 1, body = "first", created_at = "2026-01-01" },
      },
      provenance = { root = "/tmp/project", files = { "b.lua", "a.lua" } },
    }

    local payload_a = Payload.build_payload(context, opts)
    local payload_b = Payload.build_payload(context, opts)

    assert.are.same({ "c1", "c2" }, { payload_a.items[1].id, payload_a.items[2].id })
    assert.are.same(Payload.serialize(payload_a), Payload.serialize(payload_b))
  end)

  it("renders compact human-readable wire format", function()
    local payload = Payload.build_payload({
      mode = "commit_range",
      context_id = "/tmp/project::review",
      root = "/tmp/project",
      revisions = { "main" },
      revision_anchors = {
        { token = "main", commit = "5ffe8dc945e7f3d37fa56a9931cebb718834050e" },
      },
    }, {
      review_meta = {
        mode = "commit_range",
        revisions = { "main" },
      },
      items = {
        {
          id = "c-1",
          file_path = "doc/commentry.txt",
          line_start = 45,
          line_end = 48,
          line_side = "head",
          comment_type = "note",
          body = "Adding a comment",
        },
      },
      provenance = { root = "/tmp/project" },
    })

    local rendered = Payload.render_compact(payload)
    assert.is_truthy(rendered:find("COMMENTRY_REVIEW_V1", 1, true))
    assert.is_truthy(rendered:find("mode: commit_range", 1, true))
    assert.is_truthy(rendered:find("context: /tmp/project::review", 1, true))
    assert.is_truthy(rendered:find("anchors: main=5ffe8dc945e7", 1, true))
    assert.is_truthy(rendered:find("1. doc/commentry.txt:45-48 [head/note] id=c-1", 1, true))
    assert.is_truthy(rendered:find("| Adding a comment", 1, true))
  end)

  it("has no filesystem or store side effects while building/serializing", function()
    local Store = require("commentry.store")
    local original_store_write = Store.write
    local original_writefile = vim.fn.writefile
    local store_write_calls = 0
    local writefile_calls = 0

    Store.write = function(...)
      store_write_calls = store_write_calls + 1
      return original_store_write(...)
    end
    vim.fn.writefile = function(...)
      writefile_calls = writefile_calls + 1
      return original_writefile(...)
    end

    local scenarios = {
      {
        context = { context_id = "ctx-1" },
        opts = { items = { { id = "c1", body = "draft" } } },
      },
      {
        context = { context_id = "ctx-2" },
        opts = {
          items = { { id = "c2", body = "draft2" } },
          provenance = { root = "/tmp/project", files = { "lua/commentry/init.lua" } },
        },
      },
    }

    for _, scenario in ipairs(scenarios) do
      local payload = Payload.build_payload(scenario.context, scenario.opts)
      Payload.serialize(payload)
    end

    Store.write = original_store_write
    vim.fn.writefile = original_writefile

    assert.are.same(0, store_write_calls)
    assert.are.same(0, writefile_calls)
  end)

  it("extracts only active items and preserves projected fields with thread linkage", function()
    local fixture = load_fixture("codex_payload_active_vs_stale.json")
    local payload = Payload.build_payload(fixture.context, {
      items = fixture.comments,
      threads = fixture.threads,
    })

    assert.are.same(2, #payload.items)
    assert.are.same("c-active-1", payload.items[1].id)
    assert.are.same("ctx-payload-fixture", payload.items[1].diff_id)
    assert.are.same("a.lua", payload.items[1].file_path)
    assert.are.same(3, payload.items[1].line_number)
    assert.are.same("head", payload.items[1].line_side)
    assert.are.same("suggestion", payload.items[1].comment_type)
    assert.are.same("active thread comment", payload.items[1].body)
    assert.are.same("t-a-head-3", payload.items[1].thread_parent_id)
    assert.is_nil(payload.items[1].status)

    assert.are.same("c-active-2", payload.items[2].id)
    assert.are.same("praise", payload.items[2].comment_type)
    assert.are.same("active detached comment", payload.items[2].body)
    assert.is_nil(payload.items[2].thread_parent_id)
  end)

  it("keeps active extraction in parity with comments exportable_comments semantics", function()
    local fixture = load_fixture("codex_payload_active_vs_stale.json")
    local context_id = fixture.context.context_id
    local comments = load_comments_with_store({
      store = {
        path_for_context = function()
          return "/tmp/project/.commentry/contexts/ctx/commentry.json"
        end,
        read = function()
          return {
            project_root = "/tmp/project",
            context_id = context_id,
            comments = fixture.comments,
            threads = fixture.threads,
          }
        end,
        write = function()
          return true
        end,
      },
      diffview = {
        resolve_review_context = function()
          return { context_id = context_id, root = "/tmp/project" }, nil
        end,
      },
    })

    local ok = comments.load_for_view({ git_root = "/tmp/project" })
    assert.is_true(ok)

    local exportable = comments.exportable_comments(context_id)
    local extracted = Payload.extract_active_items(fixture.comments, { threads = fixture.threads })

    assert.are.same(#exportable, #extracted)
    for index, comment in ipairs(exportable) do
      local projected = extracted[index]
      assert.are.same(comment.id, projected.id)
      assert.are.same(comment.diff_id, projected.diff_id)
      assert.are.same(comment.file_path, projected.file_path)
      assert.are.same(comment.line_number, projected.line_number)
      assert.are.same(comment.line_side, projected.line_side)
      assert.are.same(comment.comment_type or "note", projected.comment_type)
      assert.are.same(comment.body, projected.body)
      assert.are.same(comment.status, projected.status)
    end
  end)

  it("produces safe, scoped payload in full send flow with mixed stale/active and mixed paths", function()
    local fixture = load_fixture("codex_payload_send_mixed_paths.json")
    local exported_context_ids = {}
    local captured_payloads = {}
    local send = load_send_with_stubs({
      config = {
        codex = {
          adapter = {
            select = "sidekick",
            fallback = nil,
          },
        },
      },
      diffview = {
        current_file_context = function()
          return {
            file_path = "lua/commentry/codex/payload.lua",
            line_number = 10,
            line_side = "head",
            view = { id = "view-mixed" },
          },
            nil
        end,
        resolve_review_context = function()
          return vim.deepcopy(fixture.review_context), nil
        end,
      },
      comments = {
        context_id_for_view = function()
          return fixture.contexts.active, nil
        end,
        exportable_comments = function(context_id)
          exported_context_ids[#exported_context_ids + 1] = context_id
          return vim.deepcopy(fixture.comments_by_context[context_id] or {})
        end,
      },
      payload = Payload,
      adapter = {
        error = function(code)
          if code == "NO_TARGET" then
            return { code = "NO_TARGET", message = "No target adapter configured.", retryable = false }
          end
          return { code = "INTERNAL_ERROR", message = "Internal adapter error.", retryable = false }
        end,
        send = function(payload)
          captured_payloads[#captured_payloads + 1] = vim.deepcopy(payload)
          return true, nil, { dispatched_items = #payload.items }
        end,
      },
      sidekick = {
        current_target = function()
          return { session_id = "session-mixed" }
        end,
        send = function(payload)
          captured_payloads[#captured_payloads + 1] = vim.deepcopy(payload)
          return true, nil, { dispatched_items = #payload.items }
        end,
      },
    })

    local result_first = send.send_current_review({})
    local result_second = send.send_current_review({})

    assert.is_true(result_first.ok)
    assert.is_true(result_second.ok)
    assert.are.same({ fixture.contexts.active, fixture.contexts.active }, exported_context_ids)
    assert.are.same(2, #captured_payloads)

    local payload = captured_payloads[1]
    assert.are.same(fixture.contexts.active, payload.context.context_id)
    assert.are.same("/tmp/project", payload.context.root)
    assert.are.same("/tmp/project", payload.provenance.root)
    assert.are.same(3, #payload.items)
    assert.are.same(
      { "c-active-abs-outside", "c-active-abs-in-repo", "c-active-rel" },
      { payload.items[1].id, payload.items[2].id, payload.items[3].id }
    )
    assert.is_nil(payload.items[1].file_path)
    assert.are.same("lua/commentry/codex/send.lua", payload.items[2].file_path)
    assert.are.same("lua/commentry/codex/payload.lua", payload.items[3].file_path)
    assert_no_absolute_paths(payload.items)
    assert_no_absolute_paths(payload.provenance.files)
    assert.are.same(Payload.serialize(captured_payloads[1]), Payload.serialize(captured_payloads[2]))
  end)
end)
