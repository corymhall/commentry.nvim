---@module 'luassert'

local Store = require("commentry.store")

local function make_temp_dir()
  local path = vim.fn.tempname()
  vim.fn.mkdir(path, "p")
  return path
end

local function sample_store(root)
  return {
    project_root = root,
    context_id = "ctx-working-tree",
    comments = {
      {
        id = "c1",
        context_id = "ctx-working-tree",
        file_path = "lua/commentry/store.lua",
        line_start = 12,
        line_end = 12,
        line_side = "head",
        comment_type = "note",
        body = "Looks good.",
        created_at = "2026-02-21T00:00:00Z",
        updated_at = "2026-02-21T00:00:00Z",
      },
    },
    threads = {
      {
        id = "t1",
        context_id = "ctx-working-tree",
        file_path = "lua/commentry/store.lua",
        line_start = 12,
        line_end = 12,
        line_side = "head",
        comment_ids = { "c1" },
      },
    },
    file_reviews = {
      ["lua/commentry/store.lua"] = true,
    },
  }
end

describe("commentry.store", function()
  it("builds context-scoped path under project root", function()
    local root = make_temp_dir()
    local path, err = Store.path_for_context(root, "ctx/feature:abc")
    assert.is_nil(err)
    local resolved_root = vim.uv.fs_realpath(vim.fs.normalize(root)) or vim.fs.normalize(root)
    local expected = vim.fs.joinpath(vim.fs.normalize(resolved_root), ".commentry", "contexts", "ctx_feature_abc", "commentry.json")
    assert.are.same(expected, path)
  end)

  it("rejects invalid project root", function()
    local path, err = Store.path_for_context("", "ctx")
    assert.is_nil(path)
    assert.are.same("project_root is required", err)
  end)

  it("rejects missing context id", function()
    local root = make_temp_dir()
    local path, err = Store.path_for_context(root, "")
    assert.is_nil(path)
    assert.are.same("context_id is required", err)
  end)

  it("rejects missing project root directory", function()
    local path, err = Store.path_for_context("/nonexistent/path", "ctx")
    assert.is_nil(path)
    assert.are.same("project_root is not a directory", err)
  end)

  it("rejects invalid store data on write", function()
    local ok, err = Store.write("/tmp/commentry.json", {})
    assert.is_false(ok)
    assert.is_table(err)
  end)

  it("persists store data", function()
    local root = make_temp_dir()
    local path = Store.path_for_context(root, "ctx-working-tree")
    local store = sample_store(root)

    local ok, err = Store.write(path, store)
    assert.is_true(ok)
    assert.is_nil(err)

    local data, read_err = Store.read(path)
    assert.is_nil(read_err)
    assert.are.same(store, data)
  end)

  it("treats non-zero writefile return as write failure", function()
    local root = make_temp_dir()
    local path = Store.path_for_context(root, "ctx-working-tree")
    local store = sample_store(root)
    local original_writefile = vim.fn.writefile

    vim.fn.writefile = function()
      return 1
    end

    local ok, err = Store.write(path, store)

    vim.fn.writefile = original_writefile

    assert.is_false(ok)
    assert.are.same("write_failed", err)
  end)

  it("returns not_found for missing store", function()
    local root = make_temp_dir()
    local path = Store.path_for_context(root, "ctx-working-tree")

    local data, err = Store.read(path)
    assert.is_nil(data)
    assert.are.same("not_found", err)
  end)

  it("rejects invalid v2 comment and thread fields", function()
    local store = {
      project_root = "root",
      context_id = "ctx",
      comments = {
        {
          id = "c1",
          context_id = "ctx",
          file_path = "lua/commentry/store.lua",
          line_start = 0,
          line_end = -1,
          line_side = "middle",
          comment_type = "feedback",
          body = "Bad anchor",
          created_at = "",
          updated_at = "",
        },
      },
      threads = {
        {
          id = "t1",
          context_id = "ctx",
          file_path = "lua/commentry/store.lua",
          line_start = -1,
          line_end = 0,
          line_side = "side",
          comment_ids = { "c1" },
        },
      },
      file_reviews = {
        ["lua/commentry/store.lua"] = "yes",
      },
    }

    local ok, errors = Store.validate(store)
    assert.is_false(ok)
    assert.is_table(errors)

    local combined = table.concat(errors, "\n")
    assert.is_true(combined:find("line_start", 1, true) ~= nil)
    assert.is_true(combined:find("line_end", 1, true) ~= nil)
    assert.is_true(combined:find("line_side", 1, true) ~= nil)
    assert.is_true(combined:find("comment_type", 1, true) ~= nil)
    assert.is_true(combined:find("file_reviews", 1, true) ~= nil)
  end)

  it("accepts configured custom comment types", function()
    local Config = require("commentry.config")
    local original_comment_types = Config.comment_types

    Config.comment_types = { "note", "question" }

    local store = sample_store("/tmp/project")
    store.comments[1].comment_type = "question"
    local ok, errors = Store.validate(store)

    Config.comment_types = original_comment_types

    assert.is_true(ok)
    assert.are.same({}, errors)
  end)

  it("creates distinct context paths for working tree and commit range contexts", function()
    local root = make_temp_dir()
    local working_tree_path, working_tree_err = Store.path_for_context(root, "ctx-working-tree")
    local commit_range_path, commit_range_err = Store.path_for_context(root, "ctx-main...HEAD")

    assert.is_nil(working_tree_err)
    assert.is_nil(commit_range_err)
    assert.is_true(working_tree_path ~= commit_range_path)
  end)

  it("sanitizes commit-range context ids into filesystem-safe directories", function()
    local root = make_temp_dir()
    local path, err = Store.path_for_context(root, "ctx/main...feature:abc")

    assert.is_nil(err)
    assert.is_true(path:find("ctx_main...feature_abc", 1, true) ~= nil)
  end)
end)
