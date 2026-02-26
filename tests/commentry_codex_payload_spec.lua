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
    assert.are.same(".", payload.provenance.root)
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
        expected_root = ".",
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
        expected_root = ".",
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
end)
