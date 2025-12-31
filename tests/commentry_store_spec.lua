local MiniTest = require("mini.test")
local expect = MiniTest.expect

local Store = require("commentry.store")

local T = MiniTest.new_set()

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

T["path_for_project builds path under project root"] = function()
  local root = make_temp_dir()
  local path, err = Store.path_for_project(root)
  expect.equality(err, nil)
  local expected = vim.fs.joinpath(vim.fs.normalize(root), ".commentry", "commentry.json")
  expect.equality(path, expected)
end

T["write/read persists store"] = function()
  local root = make_temp_dir()
  local path = Store.path_for_project(root)
  local store = sample_store(root)

  local ok, err = Store.write(path, store)
  expect.equality(ok, true)
  expect.equality(err, nil)

  local data, read_err = Store.read(path)
  expect.equality(read_err, nil)
  expect.equality(data, store)
end

T["validate rejects invalid line anchors"] = function()
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
  expect.equality(ok, false)
  expect.equality(type(errors), "table")

  local combined = table.concat(errors, "\n")
  expect.equality(combined:find("line_number", 1, true) ~= nil, true)
  expect.equality(combined:find("line_side", 1, true) ~= nil, true)
end

return T
