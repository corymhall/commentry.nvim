---@module 'luassert'

local Review = require("commentry.review")

local function git(root, args)
  local cmd = { "git", "-C", root }
  vim.list_extend(cmd, args)
  local result = vim.system(cmd, { text = true }):wait()
  assert.are.same(0, result.code, result.stderr)
  return vim.trim(result.stdout or "")
end

local function local_rev()
  return setmetatable({}, {
    __tostring = function()
      return "LOCAL"
    end,
  })
end

local function entry(path, status, base, head)
  return {
    path = path,
    status = status,
    revs = { a = base, b = head },
  }
end

describe("commentry.review", function()
  it("keeps fingerprints stable across working tree, index, commit, and push lifecycle", function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    git(root, { "init", "-q" })
    git(root, { "config", "user.name", "Commentry Test" })
    git(root, { "config", "user.email", "commentry@example.com" })

    vim.fn.writefile({ "before" }, vim.fs.joinpath(root, "file.txt"))
    git(root, { "add", "file.txt" })
    git(root, { "commit", "-qm", "base" })
    local base_commit = git(root, { "rev-parse", "HEAD" })

    vim.fn.writefile({ "after" }, vim.fs.joinpath(root, "file.txt"))
    local working = entry("file.txt", "M", { commit = base_commit }, local_rev())
    local working_snapshot = Review.snapshots(root, { working })[working]

    git(root, { "add", "file.txt" })
    local staged = entry("file.txt", "M", { commit = base_commit }, { stage = 0 })
    local staged_snapshot = Review.snapshots(root, { staged })[staged]

    git(root, { "commit", "-qm", "change" })
    local head_commit = git(root, { "rev-parse", "HEAD" })
    local committed = entry("file.txt", "M", { commit = base_commit }, { commit = head_commit })
    local committed_snapshot = Review.snapshots(root, { committed })[committed]

    assert.are.same(working_snapshot.fingerprint, staged_snapshot.fingerprint)
    assert.are.same(staged_snapshot.fingerprint, committed_snapshot.fingerprint)
    assert.are.same(working_snapshot.base, committed_snapshot.base)
    assert.are.same(working_snapshot.head, committed_snapshot.head)
  end)

  it("changes the fingerprint when either displayed endpoint changes", function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    git(root, { "init", "-q" })
    git(root, { "config", "user.name", "Commentry Test" })
    git(root, { "config", "user.email", "commentry@example.com" })

    vim.fn.writefile({ "base" }, vim.fs.joinpath(root, "file.txt"))
    git(root, { "add", "file.txt" })
    git(root, { "commit", "-qm", "base" })
    local base_commit = git(root, { "rev-parse", "HEAD" })

    vim.fn.writefile({ "first" }, vim.fs.joinpath(root, "file.txt"))
    local first = entry("file.txt", "M", { commit = base_commit }, local_rev())
    local first_snapshot = Review.snapshots(root, { first })[first]

    vim.fn.writefile({ "second" }, vim.fs.joinpath(root, "file.txt"))
    local second = entry("file.txt", "M", { commit = base_commit }, local_rev())
    local second_snapshot = Review.snapshots(root, { second })[second]

    assert.is_true(first_snapshot.fingerprint ~= second_snapshot.fingerprint)
  end)

  it("fingerprints unsaved displayed local-buffer content", function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    git(root, { "init", "-q" })
    git(root, { "config", "user.name", "Commentry Test" })
    git(root, { "config", "user.email", "commentry@example.com" })

    vim.fn.writefile({ "base" }, vim.fs.joinpath(root, "file.txt"))
    git(root, { "add", "file.txt" })
    git(root, { "commit", "-qm", "base" })
    local base_commit = git(root, { "rev-parse", "HEAD" })
    vim.fn.writefile({ "disk" }, vim.fs.joinpath(root, "file.txt"))

    local disk_entry = entry("file.txt", "M", { commit = base_commit }, local_rev())
    local disk_snapshot = Review.snapshots(root, { disk_entry })[disk_entry]

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "unsaved" })
    vim.bo[bufnr].modified = true
    local buffer_entry = entry("file.txt", "M", { commit = base_commit }, local_rev())
    buffer_entry.layout = { b = { file = { bufnr = bufnr } } }
    local buffer_snapshot = Review.snapshots(root, { buffer_entry })[buffer_entry]
    vim.api.nvim_buf_delete(bufnr, { force = true })

    assert.is_true(disk_snapshot.fingerprint ~= buffer_snapshot.fingerprint)
  end)

  it("represents added and deleted endpoints as absent", function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    git(root, { "init", "-q" })
    git(root, { "config", "user.name", "Commentry Test" })
    git(root, { "config", "user.email", "commentry@example.com" })

    vim.fn.writefile({ "content" }, vim.fs.joinpath(root, "file.txt"))
    local added = entry("file.txt", "?", { stage = 0 }, local_rev())
    local added_snapshot = Review.snapshots(root, { added })[added]
    assert.are.same("absent", added_snapshot.base)

    git(root, { "add", "file.txt" })
    git(root, { "commit", "-qm", "add" })
    local commit = git(root, { "rev-parse", "HEAD" })
    local deleted = entry("file.txt", "D", { commit = commit }, local_rev())
    local deleted_snapshot = Review.snapshots(root, { deleted })[deleted]
    assert.are.same("absent", deleted_snapshot.head)
  end)
end)
