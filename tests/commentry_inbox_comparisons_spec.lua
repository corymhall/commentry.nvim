local Render = require("commentry.inbox.render")
local Source = require("commentry.inbox.source")

describe("file excerpts", function()
  it("tracks a high-line selection through insertions and refuses changed or ambiguous code", function()
    local directory = vim.fn.tempname()
    vim.fn.mkdir(directory, "p")
    directory = (vim.uv or vim.loop).fs_realpath(directory)
    local path = directory .. "/large.lua"
    local lines = {}
    for i = 1, 1200 do
      lines[i] = "-- line " .. i
    end
    lines[1000], lines[1001], lines[1002] = "-- before selection", "return workers", "-- after selection"
    vim.fn.writefile(lines, path)
    local thread = {
      project = directory,
      source = {
        kind = "file",
        path = "large.lua",
        first = 1001,
        last = 1001,
        excerpt_first = 1000,
        lines = { lines[1000], lines[1001], lines[1002] },
        filetype = "lua",
      },
      comparisons = {},
    }
    local ok, err = pcall(function()
      table.insert(lines, 1, "-- inserted above")
      vim.fn.writefile(lines, path)
      assert.are.same(1002, Source.locate(thread).first)
      local comparison = Source.compare(thread, "since", 4)
      assert.are.same(1001, comparison.current_first)
      assert.are.same(1002, comparison.current_source.first)
      assert.is_nil(comparison.current_source.excerpt_first)
      assert.is_false(comparison.outdated)
      assert.are.same({ "-- before selection", "return workers", "-- after selection" }, comparison.lines)
      lines[1002] = "return other_workers"
      vim.fn.writefile(lines, path)
      assert.is_nil(Source.locate(thread))
      local uncertain = Source.compare(thread, "since", 4)
      assert.is_true(uncertain.outdated)
      assert.is_true(uncertain.unlocated)
      assert.is_nil(uncertain.current_source)
      assert.are.same("return workers", uncertain.lines[2])
      local sections = Source.sections(thread)
      assert.are.same(1000, sections[1].comparison.first)
      lines[1002] = "return workers"
      vim.list_extend(lines, thread.source.lines)
      vim.fn.writefile(lines, path)
      assert.is_nil(Source.locate(thread))
    end)
    vim.fn.delete(directory, "rf")
    assert.is_true(ok, tostring(err))
  end)
end)

describe("inbox comparison collection", function()
  it("renders every attached diff with its label and independent line numbers", function()
    local thread = { title = "Review these changes", source = { kind = "text", lines = {} }, comparisons = {} }
    for index = 1, 10 do
      thread.comparisons[index] = {
        label = "File " .. index,
        author = "Agent",
        at = "2026-10-19T12:00:00Z",
        before = "old " .. index .. "\n",
        after = "new " .. index .. "\n",
      }
    end
    local sections = Source.sections(thread)
    local buf = vim.api.nvim_create_buf(false, true)
    local ok, err = pcall(function()
      Render.highlights()
      Render.source({ source_buf = buf }, thread, sections)
      local contents = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local text = table.concat(contents, "\n")
      assert.is_true(
        text:find("Saved comparison / File 1\n", 1, true) < text:find("Supporting comparison / File 10", 1, true)
      )
      for index = 1, 10 do
        assert.is_truthy(
          text:find((index == 1 and "Saved comparison / File " or "Supporting comparison / File ") .. index, 1, true)
        )
        assert.is_truthy(text:find("-old " .. index .. "\n+new " .. index, 1, true))
      end
      local added = 0
      local ns = vim.api.nvim_get_namespaces()["commentry.inbox.ui"]
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
        local row, detail = mark[2], mark[4]
        if contents[row + 1]:sub(1, 5) == "+new " and detail.virt_text then
          added = added + 1
          assert.is_truthy(detail.virt_text[1][1]:find("1", 1, true))
        end
      end
      assert.are.same(10, added)
    end)
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.is_true(ok, tostring(err))
  end)
end)

describe("review presentation", function()
  local function comparison(id, label)
    return { id = id, label = label, author = "Agent", at = "2026-10-20T10:00:00Z", before = "old\n", after = "new\n" }
  end

  it("keeps the chosen explanation visible while additional evidence starts folded", function()
    local thread = {
      id = "review-presentation",
      source = { kind = "text", lines = { "Original context" } },
      primary_comparison = "example",
      comparisons = { comparison("implementation", "Parser implementation"), comparison("example", "Visible output") },
    }
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_get_current_win()
    local previous = vim.api.nvim_win_get_buf(win)
    vim.api.nvim_win_set_buf(win, buf)
    local view = { source_buf = buf, source_win = win }
    local ok, err = pcall(function()
      Render.source(view, thread, Source.sections(thread))
      assert.matches("Primary comparison / Visible output", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
      assert.are.same(-1, vim.fn.foldclosed(view.source_sections[1].first))
      assert.are.same(view.source_sections[2].first, vim.fn.foldclosed(view.source_sections[2].first))
      vim.api.nvim_win_set_cursor(win, { view.source_sections[2].first, 0 })
      vim.cmd("normal! zo")
      thread.comparisons[#thread.comparisons + 1] = comparison("tests", "Regression tests")
      Render.source(view, thread, Source.sections(thread))
      assert.are.same("comparison:example", view.source_sections[1].id)
      assert.are.same(-1, vim.fn.foldclosed(view.source_sections[2].first))
      assert.are.same(view.source_sections[3].first, vim.fn.foldclosed(view.source_sections[3].first))
      thread.primary_comparison = "tests"
      Render.source(view, thread, Source.sections(thread))
      assert.are.same("comparison:tests", view.source_sections[1].id)
      assert.are.same(-1, vim.fn.foldclosed(view.source_sections[1].first))
      assert.are.same(view.source_sections[3].first, vim.fn.foldclosed(view.source_sections[3].first))
    end)
    vim.api.nvim_win_set_buf(
      win,
      vim.api.nvim_buf_is_valid(previous) and previous or vim.api.nvim_create_buf(false, true)
    )
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.is_true(ok, tostring(err))
  end)

  it("shows the current review and folds an original finding when a newer agent message exists", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_get_current_win()
    local previous = vim.api.nvim_win_get_buf(win)
    vim.api.nvim_win_set_buf(win, buf)
    local thread = {
      id = "revised-review-presentation",
      title = "References appear as literal markup",
      queue = {},
      review = {
        summary = "Backticks prevent references from resolving. The local fix removes them.",
        author = "Agent",
      },
      messages = {
        {
          author = "Agent",
          at = "2026-10-20T10:00:00Z",
          body = "Old confusing explanation\nwith implementation details",
        },
        { author = "You", at = "2026-10-20T10:01:00Z", body = "Does this affect Java?" },
        { author = "Agent", at = "2026-10-20T10:02:00Z", body = "Yes, Java uses the same converted references." },
      },
    }
    local ok, err = pcall(function()
      local view = { thread_buf = buf, thread_win = win, outdated = {} }
      Render.conversation(view, thread)
      local contents = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      assert.is_true(contents:find("Backticks prevent", 1, true) < contents:find("Discussion", 1, true))
      assert.is_truthy(contents:find("Old confusing explanation", 1, true))
      local original = view.message_presentation.messages[1]
      assert.are.same(original.first, vim.fn.foldclosed(original.first))
      local reply = assert(contents:find("Does this affect Java?", 1, true))
      assert.is_true(reply < assert(contents:find("Reply /", 1, true)))
      -- With no newer agent reply, the original finding is the latest agent message.
      table.remove(thread.messages)
      Render.conversation(view, thread)
      for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if line == "Old confusing explanation" then
          assert.are.same(-1, vim.fn.foldclosed(row))
        end
      end
    end)
    vim.api.nvim_win_set_buf(
      win,
      vim.api.nvim_buf_is_valid(previous) and previous or vim.api.nvim_create_buf(false, true)
    )
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.is_true(ok, tostring(err))
  end)
end)
