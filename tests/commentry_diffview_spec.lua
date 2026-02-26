---@module 'luassert'

describe("commentry.diffview hover preview", function()
  local original_diffview
  local original_comments
  local original_store
  local original_config
  local original_diffview_lib
  local original_create_autocmd
  local original_schedule
  local original_buf_is_valid
  local original_clear_namespace
  local original_set_extmark

  local function load_comments_with_stubs(stubs)
    original_store = package.loaded["commentry.store"]
    original_diffview = package.loaded["commentry.diffview"]
    original_comments = package.loaded["commentry.comments"]

    package.loaded["commentry.store"] = stubs.store
    package.loaded["commentry.diffview"] = stubs.diffview
    package.loaded["commentry.comments"] = nil

    return require("commentry.comments")
  end

  before_each(function()
    original_store = package.loaded["commentry.store"]
    original_diffview = package.loaded["commentry.diffview"]
    original_comments = package.loaded["commentry.comments"]
    original_config = package.loaded["commentry.config"]
    original_diffview_lib = package.loaded["diffview.lib"]
    original_create_autocmd = vim.api.nvim_create_autocmd
    original_schedule = vim.schedule
    original_buf_is_valid = vim.api.nvim_buf_is_valid
    original_clear_namespace = vim.api.nvim_buf_clear_namespace
    original_set_extmark = vim.api.nvim_buf_set_extmark
  end)

  after_each(function()
    package.loaded["commentry.store"] = original_store
    package.loaded["commentry.diffview"] = original_diffview
    package.loaded["commentry.comments"] = original_comments
    package.loaded["commentry.config"] = original_config
    package.loaded["diffview.lib"] = original_diffview_lib
    vim.api.nvim_create_autocmd = original_create_autocmd
    vim.schedule = original_schedule
    vim.api.nvim_buf_is_valid = original_buf_is_valid
    vim.api.nvim_buf_clear_namespace = original_clear_namespace
    vim.api.nvim_buf_set_extmark = original_set_extmark
  end)

  it("renders and clears hover preview extmarks", function()
    local clear_calls = 0
    local extmark_calls = 0
    local extmark_opts = nil

    vim.api.nvim_buf_is_valid = function()
      return true
    end
    vim.api.nvim_buf_clear_namespace = function()
      clear_calls = clear_calls + 1
    end
    vim.api.nvim_buf_set_extmark = function(_, _, _, _, opts)
      extmark_calls = extmark_calls + 1
      extmark_opts = opts
      return 1
    end

    package.loaded["commentry.diffview"] = nil
    local Diffview = require("commentry.diffview")

    Diffview.render_hover_preview(1, 4, {
      { body = "one" },
      { body = "two\nlines" },
    })

    assert.are.same(1, extmark_calls)
    assert.is_table(extmark_opts.virt_lines)
    assert.are.same("[note] one", extmark_opts.virt_lines[1][1][1])
    assert.are.same("[note] two lines", extmark_opts.virt_lines[2][1][1])

    Diffview.clear_hover_preview(1)
    assert.is_true(clear_calls >= 2)
  end)

  it("aggregates marker labels by range start and comment type counts", function()
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

    Diffview.render_comment_markers(1, {
      { line_start = 4, line_end = 6, comment_type = "note" },
      { line_start = 4, line_end = 6, comment_type = "note" },
      { line_start = 4, line_end = 6, comment_type = "issue" },
    })

    assert.are.same(1, #marker_calls)
    assert.are.same(3, marker_calls[1].line)
    assert.are.same("[issue,note:2]", marker_calls[1].opts.virt_text[1][1])
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

  it("shows preview only for current commented line and clears otherwise", function()
    local rendered = nil
    local cleared = 0

    local comments = load_comments_with_stubs({
      store = {
        path_for_project = function()
          return "/tmp/project/.commentry/commentry.json"
        end,
        read = function()
          return {
            project_root = "/tmp/project",
            diff_id = "/tmp/project",
            comments = {
              {
                id = "c1",
                diff_id = "/tmp/project",
                file_path = "file.lua",
                line_number = 7,
                line_start = 7,
                line_end = 9,
                line_side = "head",
                comment_type = "issue",
                body = "hover me",
                line_content = "line seven",
              },
            },
            threads = {
              {
                id = "t-/tmp/project-file.lua|head|7",
                diff_id = "/tmp/project",
                file_path = "file.lua",
                line_number = 7,
                line_start = 7,
                line_end = 9,
                line_side = "head",
                comment_ids = { "c1" },
              },
            },
          }
        end,
        write = function()
          return true
        end,
      },
      diffview = {
        current_file_context = function()
          return {
            file_path = "file.lua",
            line_number = 7,
            line_side = "head",
            bufnr = 1,
            view = { git_root = "/tmp/project" },
          }
        end,
        render_comment_markers = function()
          return
        end,
        render_hover_preview = function(bufnr, line_number, line_comments)
          rendered = { bufnr = bufnr, line_number = line_number, line_comments = line_comments }
        end,
        clear_hover_preview = function()
          cleared = cleared + 1
        end,
      },
    })

    comments.load_for_view({ git_root = "/tmp/project" })
    local shown = comments.refresh_hover_preview()
    assert.is_true(shown)
    assert.is_table(rendered)
    assert.are.same(7, rendered.line_number)
    assert.are.same("c1", rendered.line_comments[1].id)

    rendered = nil
    package.loaded["commentry.diffview"].current_file_context = function()
      return {
        file_path = "file.lua",
        line_number = 8,
        line_side = "head",
        bufnr = 1,
        view = { git_root = "/tmp/project" },
      }
    end

    local shown_in_range = comments.refresh_hover_preview()
    assert.is_true(shown_in_range)
    assert.is_table(rendered)
    assert.are.same("c1", rendered.line_comments[1].id)

    rendered = nil
    package.loaded["commentry.diffview"].current_file_context = function()
      return {
        file_path = "file.lua",
        line_number = 10,
        line_side = "head",
        bufnr = 1,
        view = { git_root = "/tmp/project" },
      }
    end

    local shown_none = comments.refresh_hover_preview()
    assert.is_false(shown_none)
    assert.is_nil(rendered)
    assert.are.same(1, cleared)
  end)

  it("does not bleed hover previews across base/head sides on the same line", function()
    local rendered = nil
    local comments = load_comments_with_stubs({
      store = {
        path_for_project = function()
          return "/tmp/project/.commentry/commentry.json"
        end,
        read = function()
          return {
            project_root = "/tmp/project",
            diff_id = "/tmp/project",
            comments = {
              {
                id = "c-head",
                diff_id = "/tmp/project",
                file_path = "file.lua",
                line_number = 7,
                line_side = "head",
                body = "head side",
              },
              {
                id = "c-base",
                diff_id = "/tmp/project",
                file_path = "file.lua",
                line_number = 7,
                line_side = "base",
                body = "base side",
              },
            },
            threads = {
              {
                id = "t-head",
                diff_id = "/tmp/project",
                file_path = "file.lua",
                line_number = 7,
                line_side = "head",
                comment_ids = { "c-head" },
              },
              {
                id = "t-base",
                diff_id = "/tmp/project",
                file_path = "file.lua",
                line_number = 7,
                line_side = "base",
                comment_ids = { "c-base" },
              },
            },
          }
        end,
        write = function()
          return true
        end,
      },
      diffview = {
        current_file_context = function()
          return {
            file_path = "file.lua",
            line_number = 7,
            line_side = "head",
            bufnr = 1,
            view = { git_root = "/tmp/project" },
          }
        end,
        render_comment_markers = function()
          return
        end,
        render_hover_preview = function(_, _, line_comments)
          rendered = line_comments
        end,
        clear_hover_preview = function()
          return
        end,
      },
    })

    comments.load_for_view({ git_root = "/tmp/project" })
    local shown = comments.refresh_hover_preview()
    assert.is_true(shown)
    assert.is_table(rendered)
    assert.are.same(1, #rendered)
    assert.are.same("c-head", rendered[1].id)
  end)

  it("wires cursor movement and hold handlers to hover refresh", function()
    local autocmds = {}
    local refresh_calls = 0

    vim.api.nvim_create_autocmd = function(events, opts)
      autocmds[#autocmds + 1] = { events = events, opts = opts }
    end
    vim.schedule = function(cb)
      cb()
    end

    package.loaded["commentry.config"] = {
      augroup = 1,
      diffview = { auto_attach = true },
      ns = 1,
    }
    package.loaded["commentry.comments"] = {
      load_current_view = function()
        return true
      end,
      render_current_buffer = function()
        return
      end,
      refresh_hover_preview = function()
        refresh_calls = refresh_calls + 1
        return true
      end,
    }
    package.loaded["diffview.lib"] = {
      get_current_view = function()
        return nil
      end,
    }

    package.loaded["commentry.diffview"] = nil
    local Diffview = require("commentry.diffview")

    vim.api.nvim_buf_is_valid = function()
      return true
    end

    Diffview.setup()
    assert.are.same(2, #autocmds)

    Diffview.current_file_context = function()
      return {
        file_path = "file.lua",
        line_number = 1,
        line_side = "head",
        bufnr = vim.api.nvim_get_current_buf(),
        view = {},
      }
    end
    local marked = Diffview.mark_current_buffer()
    assert.is_true(marked)

    local cursor_handler = nil
    for _, autocmd in ipairs(autocmds) do
      if type(autocmd.events) == "table"
        and autocmd.events[1] == "CursorMoved"
        and autocmd.opts.buffer == vim.api.nvim_get_current_buf() then
        cursor_handler = autocmd.opts.callback
      end
    end

    assert.is_not_nil(cursor_handler)
    cursor_handler()
    assert.are.same(1, refresh_calls)
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
    local revision_context = Diffview.resolve_review_context({ "HEAD~1..HEAD" }, { git_root = "/tmp/commentry-project" })
    local revision_context_again = Diffview.resolve_review_context({ "HEAD~1..HEAD" }, { git_root = "/tmp/commentry-project" })

    assert.are.same("working_tree", working_context.mode)
    assert.are.same("commit_range", revision_context.mode)
    assert.are.same(working_context.context_id, revision_context.context_id)
    assert.are.same(revision_context.context_id, revision_context_again.context_id)
    assert.is_truthy(revision_context.context_id:sub(-8) == "::review")
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
  end)
end)
