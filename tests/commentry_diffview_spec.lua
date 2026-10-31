local Source = require("commentry.inbox.source")
local Store = require("commentry.inbox.store")

describe("Diffview inbox capture", function()
  local root, directory, lib, buffers, origin
  local function git(args)
    local argv = { "git", "-C", root }
    vim.list_extend(argv, args)
    local result = vim.system(argv, { text = true }):wait()
    assert.are.same(0, result.code, result.stderr)
    return vim.trim(result.stdout)
  end
  local function key(buf, mode, lhs)
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
      if map.lhs:lower() == lhs:lower() then
        return map.callback
      end
    end
    error("Missing mapping " .. lhs)
  end
  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    root = vim.uv.fs_realpath(root)
    directory = vim.env.COMMENTRY_INBOX_DIR
    vim.env.COMMENTRY_INBOX_DIR = root .. "/inbox"
    lib = package.loaded["diffview.lib"]
    origin = vim.api.nvim_get_current_buf()
    buffers = {}
    git({ "init", "-q" })
    vim.fn.writefile({ "before", "old code", "after" }, root .. "/old.lua")
    git({ "add", "old.lua" })
    git({ "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-qm", "baseline" })
    local revision = git({ "rev-parse", "HEAD" })
    local layout = {}
    for _, side in ipairs({ "a", "b" }) do
      local buf = vim.api.nvim_create_buf(false, true)
      buffers[#buffers + 1] = buf
      vim.api.nvim_buf_set_name(buf, "diffview://test/" .. side .. "/virtual.lua")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "before", side == "a" and "old code" or "new code", "after" })
      vim.bo[buf].buftype = "nowrite"
      layout[side] = {
        file = {
          bufnr = buf,
          path = side == "a" and "old.lua" or "new.lua",
          rev = side == "a" and { commit = revision } or { stage = 0 },
          adapter = { ctx = { toplevel = root } },
        },
      }
    end
    git({ "mv", "old.lua", "new.lua" })
    vim.fn.writefile({ "before", "new code", "after" }, root .. "/new.lua")
    git({ "add", "new.lua" })
    package.loaded["diffview.lib"] = {
      get_current_view = function()
        return { cur_entry = { path = "new.lua", layout = layout } }
      end,
    }
    vim.api.nvim_win_set_buf(0, buffers[1])
  end)
  after_each(function()
    vim.cmd.stopinsert()
    package.loaded["diffview.lib"] = lib
    vim.api.nvim_win_set_buf(0, vim.api.nvim_buf_is_valid(origin) and origin or vim.api.nvim_create_buf(true, false))
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    vim.env.COMMENTRY_INBOX_DIR = directory
    vim.fn.delete(root, "rf")
  end)

  it("saves both displayed sides to the shared inbox with their real paths and revisions", function()
    local Diffview = require("commentry.diffview")
    require("commentry.config").setup({})
    for _, buf in ipairs(buffers) do
      require("commentry.commands").attach(buf)
    end
    -- Capture the deleted/renamed base path, even though it no longer exists.
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    key(buffers[1], "n", "mc")()
    local composer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(composer, 0, -1, false, { "Why remove this?" })
    key(composer, "n", "<C-S>")()
    local threads = assert(Store.list(root))
    assert.are.same(1, #threads)
    local first = threads[1]
    assert.are.same("old.lua", first.source.path)
    assert.are.same("old code", first.source.lines[2])
    assert.are.same("diffview:a", first.source.origin)
    assert.are.same(git({ "rev-parse", "HEAD" }), first.source.git.revision)
    assert.are.same("Why remove this?", first.messages[1].body)
    -- The same inbox operation can capture a staged range on the other side.
    vim.api.nvim_win_set_buf(0, buffers[2])
    local capture = assert(Source.capture(buffers[2], 2, 3))
    capture.body = "Review this range"
    local second = assert(Store.create(capture))
    local saved = assert(Store.get(second))
    assert.are.same("new.lua", saved.source.path)
    assert.are.same(":0", saved.source.git.revision)
    assert.are.same(git({ "rev-parse", ":0:new.lua" }), saved.source.git.blob)
    assert.are.same(3, saved.source.last)
    Diffview.refresh()
    local ns = vim.api.nvim_create_namespace("commentry.inbox.locations")
    assert.is_true(#vim.api.nvim_buf_get_extmarks(buffers[1], ns, 0, -1, {}) > 0)
    assert.is_true(#vim.api.nvim_buf_get_extmarks(buffers[2], ns, 0, -1, {}) > 0)
    local function preview(buf)
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
        if mark[4].virt_lines then
          local text = {}
          for _, line in ipairs(mark[4].virt_lines) do
            for _, chunk in ipairs(line) do
              text[#text + 1] = chunk[1]
            end
          end
          return table.concat(text, "\n")
        end
      end
    end
    assert.is_truthy(preview(buffers[1]):find("Why remove this?", 1, true))
    assert.is_truthy(preview(buffers[2]):find("Review this range", 1, true))
    local signs = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffers[2], ns, 0, -1, { details = true })) do
      if mark[4].sign_text then
        signs[mark[2] + 1] = vim.trim(mark[4].sign_text)
      end
    end
    assert.are.same("╭", signs[2])
    assert.are.same("╰", signs[3])
    -- Two topics on one line keep separate cards, even with duplicate locations.
    assert(Store.update(second, { kind = "attach", author = "Agent", label = "Same selection", source = saved.source }))
    capture.body = "Another independent question"
    assert(Store.create(capture))
    Diffview.refresh()
    local cards = preview(buffers[2])
    assert.is_truthy(cards:find("Another independent question", 1, true))
    local _, occurrences = cards:gsub("Review this range", "")
    assert.are.same(1, occurrences)
    -- Sending freezes the pending comment before replies can be added.
    assert.is_true(first.pending)
    assert(Store.enqueue(first.id, nil, { defer_delivery = true }))
    -- Resolution and replies operate on these exact inbox threads.
    assert(Store.update(first.id, { kind = "reply", author = "Agent", body = "The replacement handles retries." }))
    Diffview.refresh()
    assert.is_truthy(preview(buffers[1]):find("The replacement handles retries.", 1, true))
    assert(Store.update(first.id, { kind = "resolve", resolved = true }))
    assert.is_true(assert(Store.get(first.id)).resolved)
    Diffview.refresh()
    assert.are.same(0, #vim.api.nvim_buf_get_extmarks(buffers[1], ns, 0, -1, {}))
  end)

  it("rejects absent diff sides and never treats a scratch name as a source path", function()
    local Diffview = require("commentry.diffview")
    local context = Diffview.current_file_context(buffers[1])
    context.file.nulled = true
    assert.is_nil(Diffview.capture(buffers[1], 1, 1))
    local result = Source.capture(buffers[1], 1, 1)
    assert.is_nil(result)
    assert.are.same(0, #assert(Store.list(root)))
  end)
end)
