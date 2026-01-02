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
    diff_id = "diff-1",
    comments = {
      {
        id = "c1",
        diff_id = "diff-1",
        file_path = "lua/commentry/store.lua",
        line_number = 12,
        line_side = "head",
        body = "Looks good.",
      },
    },
    threads = {
      {
        id = "t1",
        diff_id = "diff-1",
        file_path = "lua/commentry/store.lua",
        line_number = 12,
        line_side = "head",
        comment_ids = { "c1" },
      },
    },
  }
end

describe("commentry.store", function()
  it("builds path under project root", function()
    local root = make_temp_dir()
    local path, err = Store.path_for_project(root)
    assert.is_nil(err)
    local expected = vim.fs.joinpath(vim.fs.normalize(root), ".commentry", "commentry.json")
    assert.are.same(expected, path)
  end)

  it("rejects invalid project root", function()
    local path, err = Store.path_for_project("")
    assert.is_nil(path)
    assert.are.same("project_root is required", err)
  end)

  it("rejects missing project root directory", function()
    local path, err = Store.path_for_project("/nonexistent/path")
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
    local path = Store.path_for_project(root)
    local store = sample_store(root)

    local ok, err = Store.write(path, store)
    assert.is_true(ok)
    assert.is_nil(err)

    local data, read_err = Store.read(path)
    assert.is_nil(read_err)
    assert.are.same(store, data)
  end)

  it("returns not_found for missing store", function()
    local root = make_temp_dir()
    local path = Store.path_for_project(root)

    local data, err = Store.read(path)
    assert.is_nil(data)
    assert.are.same("not_found", err)
  end)

  it("rejects invalid line anchors", function()
    local store = {
      project_root = "root",
      diff_id = "diff",
      comments = {
        {
          id = "c1",
          diff_id = "diff",
          file_path = "lua/commentry/store.lua",
          line_number = 0,
          line_side = "middle",
          body = "Bad anchor",
        },
      },
      threads = {
        {
          id = "t1",
          diff_id = "diff",
          file_path = "lua/commentry/store.lua",
          line_number = -1,
          line_side = "side",
          comment_ids = { "c1" },
        },
      },
    }

    local ok, errors = Store.validate(store)
    assert.is_false(ok)
    assert.is_table(errors)

    local combined = table.concat(errors, "\n")
    assert.is_true(combined:find("line_number", 1, true) ~= nil)
    assert.is_true(combined:find("line_side", 1, true) ~= nil)
  end)
end)
