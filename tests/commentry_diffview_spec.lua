---@module 'luassert'

describe("commentry.diffview comment cards", function()
  local original_diffview
  local original_config
  local original_diffview_lib
  local original_create_autocmd
  local original_schedule
  local original_buf_is_valid
  local original_clear_namespace
  local original_set_extmark
  local original_set_hl

  before_each(function()
    original_diffview = package.loaded["commentry.diffview"]
    original_config = package.loaded["commentry.config"]
    original_diffview_lib = package.loaded["diffview.lib"]
    original_create_autocmd = vim.api.nvim_create_autocmd
    original_schedule = vim.schedule
    original_buf_is_valid = vim.api.nvim_buf_is_valid
    original_clear_namespace = vim.api.nvim_buf_clear_namespace
    original_set_extmark = vim.api.nvim_buf_set_extmark
    original_set_hl = vim.api.nvim_set_hl
  end)

  after_each(function()
    package.loaded["commentry.diffview"] = original_diffview
    package.loaded["commentry.config"] = original_config
    package.loaded["diffview.lib"] = original_diffview_lib
    vim.api.nvim_create_autocmd = original_create_autocmd
    vim.schedule = original_schedule
    vim.api.nvim_buf_is_valid = original_buf_is_valid
    vim.api.nvim_buf_clear_namespace = original_clear_namespace
    vim.api.nvim_buf_set_extmark = original_set_extmark
    vim.api.nvim_set_hl = original_set_hl
  end)

  it("renders marker labels and persistent boxed comment cards", function()
    local marker_calls = {}
    local card_calls = {}

    vim.api.nvim_buf_is_valid = function()
      return true
    end
    vim.api.nvim_buf_clear_namespace = function()
      return
    end
    vim.api.nvim_set_hl = function()
      return
    end
    vim.api.nvim_buf_set_extmark = function(_, _, line, _, opts)
      if opts.virt_text then
        marker_calls[#marker_calls + 1] = { line = line, opts = opts }
      elseif opts.virt_lines then
        card_calls[#card_calls + 1] = { line = line, opts = opts }
      end
      return 1
    end

    package.loaded["commentry.diffview"] = nil
    local Diffview = require("commentry.diffview")

    Diffview.render_comment_markers(1, {
      { id = "c-1", line_start = 4, line_end = 6, comment_type = "note", body = "one\ntwo" },
      { id = "c-2", line_start = 4, line_end = 6, comment_type = "issue", body = "three" },
    })

    assert.are.same(1, #marker_calls)
    assert.are.same(3, marker_calls[1].line)
    assert.are.same("[issue,note]", marker_calls[1].opts.virt_text[1][1])

    assert.are.same(1, #card_calls)
    assert.are.same(3, card_calls[1].line)
    local first_card_line = card_calls[1].opts.virt_lines[1]
    assert.are.same("  ╭─ ", first_card_line[1][1])
    assert.is_true(first_card_line[2][1]:find("%[NOTE%] L4%-L6", 1, false) ~= nil)
  end)

  it("renders range gutter signs with subtle line highlights", function()
    local range_calls = {}

    vim.api.nvim_buf_is_valid = function()
      return true
    end
    vim.api.nvim_buf_clear_namespace = function()
      return
    end
    vim.api.nvim_set_hl = function()
      return
    end
    vim.api.nvim_buf_set_extmark = function(_, _, line, _, opts)
      if opts.sign_text then
        range_calls[#range_calls + 1] = { line = line, opts = opts }
      end
      return 1
    end

    package.loaded["commentry.diffview"] = nil
    local Diffview = require("commentry.diffview")

    Diffview.render_comment_markers(1, {
      { id = "c-1", line_start = 4, line_end = 6, comment_type = "issue", body = "range body" },
    })

    table.sort(range_calls, function(a, b)
      return a.line < b.line
    end)
    assert.are.same(3, #range_calls)
    assert.are.same("╭", range_calls[1].opts.sign_text)
    assert.are.same("│", range_calls[2].opts.sign_text)
    assert.are.same("╰", range_calls[3].opts.sign_text)
    assert.are.same("CommentryRangeSignIssue", range_calls[1].opts.sign_hl_group)
    assert.are.same("CommentryRangeLineIssue", range_calls[2].opts.line_hl_group)
  end)

  it("renders reviewed state indicator labels", function()
    local marker_calls = {}
    vim.api.nvim_buf_is_valid = function()
      return true
    end
    vim.api.nvim_buf_clear_namespace = function()
      return
    end
    vim.api.nvim_buf_set_extmark = function(_, _, line, _, opts)
      marker_calls[#marker_calls + 1] = { line = line, opts = opts }
      return 1
    end

    package.loaded["commentry.diffview"] = nil
    local Diffview = require("commentry.diffview")

    Diffview.render_file_review_indicator(1, true)
    Diffview.render_file_review_indicator(1, false)

    assert.are.same(2, #marker_calls)
    assert.are.same(0, marker_calls[1].line)
    assert.are.same("[reviewed]", marker_calls[1].opts.virt_text[1][1])
    assert.are.same("[unreviewed]", marker_calls[2].opts.virt_text[1][1])
  end)

  it("lists files from view and focuses target path", function()
    local focused = nil
    package.loaded["commentry.diffview"] = nil
    local Diffview = require("commentry.diffview")

    local files = {
      { path = "a.lua" },
      { path = "b.lua" },
    }
    local view = {
      files = {
        iter = function()
          local i = 0
          return function()
            i = i + 1
            if i <= #files then
              return i, files[i]
            end
          end
        end,
      },
      set_file_by_path = function(_, path)
        focused = path
      end,
    }

    local paths = Diffview.list_view_files(view)
    local ok, err = Diffview.focus_file(view, "b.lua")

    assert.are.same({ "a.lua", "b.lua" }, paths)
    assert.is_true(ok)
    assert.is_nil(err)
    assert.are.same("b.lua", focused)
  end)

  it("wires diffview lifecycle hooks and avoids cursor-hover hooks", function()
    local autocmds = {}

    vim.api.nvim_create_autocmd = function(events, opts)
      autocmds[#autocmds + 1] = { events = events, opts = opts }
    end
    vim.schedule = function(cb)
      cb()
    end
    vim.api.nvim_set_hl = function()
      return
    end

    package.loaded["commentry.config"] = {
      augroup = 1,
      diffview = { auto_attach = true, comment_cards = {} },
      ns = 1,
    }
    package.loaded["commentry.comments"] = {
      load_current_view = function()
        return true
      end,
      render_current_buffer = function()
        return
      end,
    }
    package.loaded["diffview.lib"] = {
      get_current_view = function()
        return nil
      end,
    }

    package.loaded["commentry.diffview"] = nil
    local Diffview = require("commentry.diffview")
    Diffview.setup()
    Diffview.setup()

    assert.are.same(3, #autocmds)
    assert.are.same("User", autocmds[1].events)
    assert.are.same("User", autocmds[2].events)
    assert.are.same("User", autocmds[3].events)
    assert.are.same("Commentry sync comments after diffview layout", autocmds[1].opts.desc)
    assert.are.same("Commentry mark/sync on diff buffer read", autocmds[2].opts.desc)
    assert.are.same("Commentry mark/sync on diff buffer enter", autocmds[3].opts.desc)
  end)
end)

describe("commentry review context", function()
  local original_diffview

  before_each(function()
    original_diffview = package.loaded["commentry.diffview"]
  end)

  after_each(function()
    package.loaded["commentry.diffview"] = original_diffview
  end)

  it("keeps stable review-scope context identity across revision ranges", function()
    package.loaded["commentry.diffview"] = nil
    local Diffview = require("commentry.diffview")

    local working_context = Diffview.resolve_review_context(nil, { git_root = "/tmp/commentry-project" })
    local revision_context = Diffview.resolve_review_context(
      { "HEAD~1..HEAD" },
      { git_root = "/tmp/commentry-project" }
    )
    local revision_context_again = Diffview.resolve_review_context(
      { "HEAD~1..HEAD" },
      { git_root = "/tmp/commentry-project" }
    )

    assert.are.same("working_tree", working_context.mode)
    assert.are.same("commit_range", revision_context.mode)
    assert.are.same(working_context.context_id, revision_context.context_id)
    assert.are.same(revision_context.context_id, revision_context_again.context_id)
    assert.is_truthy(revision_context.context_id:find("::review::branch::", 1, true) ~= nil)
  end)

  it("adds concrete revision anchors when revisions resolve to commits", function()
    package.loaded["commentry.diffview"] = nil
    local Diffview = require("commentry.diffview")
    local root = vim.fs.normalize(vim.uv.fs_realpath(vim.fn.getcwd()) or vim.fn.getcwd())

    local context = Diffview.resolve_review_context({ "HEAD" }, { git_root = root })

    assert.is_table(context.revision_anchors)
    assert.are.same(1, #context.revision_anchors)
    assert.are.same("HEAD", context.revision_anchors[1].token)
    assert.is_true(type(context.revision_anchors[1].commit) == "string" and #context.revision_anchors[1].commit >= 7)
    assert.is_truthy(context.context_id:find("::review::branch::", 1, true) ~= nil)
  end)
end)
