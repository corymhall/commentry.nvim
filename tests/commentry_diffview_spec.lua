---@module 'luassert'

describe("commentry.diffview comment cards", function()
  local original_diffview
  local original_config
  local original_diffview_lib
  local original_buf_is_valid
  local original_buf_line_count
  local original_clear_namespace
  local original_set_extmark
  local original_set_hl

  before_each(function()
    original_diffview = package.loaded["commentry.diffview"]
    original_config = package.loaded["commentry.config"]
    original_diffview_lib = package.loaded["diffview.lib"]
    original_buf_is_valid = vim.api.nvim_buf_is_valid
    original_buf_line_count = vim.api.nvim_buf_line_count
    original_clear_namespace = vim.api.nvim_buf_clear_namespace
    original_set_extmark = vim.api.nvim_buf_set_extmark
    original_set_hl = vim.api.nvim_set_hl
  end)

  after_each(function()
    package.loaded["commentry.diffview"] = original_diffview
    package.loaded["commentry.config"] = original_config
    package.loaded["diffview.lib"] = original_diffview_lib
    vim.api.nvim_buf_is_valid = original_buf_is_valid
    vim.api.nvim_buf_line_count = original_buf_line_count
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
    local chunks = {}
    for _, row in ipairs(card_calls[1].opts.virt_lines) do
      for _, chunk in ipairs(row) do
        chunks[#chunks + 1] = chunk[1]
      end
    end
    local card = table.concat(chunks, " ")
    assert.is_truthy(card:find("L4-L6", 1, true))
    assert.is_truthy(card:find("one", 1, true))
    assert.is_truthy(card:find("two", 1, true))
    assert.is_truthy(card:find("three", 1, true))
  end)

  it("renders question range signs, line highlights, and card styling", function()
    local range_calls = {}
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
      if opts.sign_text then
        range_calls[#range_calls + 1] = { line = line, opts = opts }
      elseif opts.virt_lines then
        card_calls[#card_calls + 1] = { line = line, opts = opts }
      end
      return 1
    end

    package.loaded["commentry.diffview"] = nil
    local Diffview = require("commentry.diffview")

    Diffview.render_comment_markers(1, {
      { id = "c-1", line_start = 4, line_end = 6, comment_type = "question", body = "range body" },
    })

    table.sort(range_calls, function(a, b)
      return a.line < b.line
    end)
    assert.are.same(3, #range_calls)
    assert.are.same({ 3, 4, 5 }, { range_calls[1].line, range_calls[2].line, range_calls[3].line })
    assert.is_string(range_calls[1].opts.sign_text)
    assert.is_string(range_calls[2].opts.line_hl_group)
    assert.are.same(1, #card_calls)
    assert.are.same("QUESTION", card_calls[1].opts.virt_lines[1][2][1])
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

  it("renders independent reviewed and partial marks in the file panel", function()
    local marks = {}
    local reviewed = { path = "reviewed.lua" }
    local pending = { path = "pending.lua" }
    local directory = {
      _node = {
        leaves = function()
          return { { data = reviewed }, { data = pending } }
        end,
      },
    }

    vim.api.nvim_buf_is_valid = function()
      return true
    end
    vim.api.nvim_buf_line_count = function()
      return 10
    end
    vim.api.nvim_buf_clear_namespace = function()
      return
    end
    vim.api.nvim_set_hl = function()
      return
    end
    vim.api.nvim_buf_set_extmark = function(_, _, row, _, opts)
      marks[#marks + 1] = { row = row, text = opts.virt_text[1][1] }
      return #marks
    end

    package.loaded["commentry.diffview"] = nil
    local Diffview = require("commentry.diffview")
    Diffview.render_file_review_panel({
      panel = {
        bufid = 5,
        components = {
          working = {
            files = {
              comp = {
                components = {
                  {
                    name = "directory",
                    context = directory,
                    lstart = 1,
                    components = {
                      { name = "file", context = reviewed, lstart = 2, components = {} },
                      { name = "file", context = pending, lstart = 3, components = {} },
                    },
                  },
                },
              },
            },
          },
        },
      },
    }, { [reviewed] = true, [pending] = false })

    assert.are.same({
      { row = 1, text = "[partial]" },
      { row = 2, text = "[reviewed]" },
    }, marks)
  end)

  it("renders active and unresolved comment counts beside file review state", function()
    local marks = {}
    local reviewed = { path = "reviewed.lua" }
    local pending = { path = "pending.lua" }

    vim.api.nvim_buf_is_valid = function()
      return true
    end
    vim.api.nvim_buf_line_count = function()
      return 10
    end
    vim.api.nvim_buf_clear_namespace = function()
      return
    end
    vim.api.nvim_set_hl = function()
      return
    end
    vim.api.nvim_buf_set_extmark = function(_, _, row, _, opts)
      local text = {}
      for _, chunk in ipairs(opts.virt_text) do
        text[#text + 1] = chunk[1]
      end
      marks[#marks + 1] = { row = row, text = table.concat(text) }
      return #marks
    end

    package.loaded["commentry.diffview"] = nil
    local Diffview = require("commentry.diffview")
    Diffview.render_file_review_panel({
      panel = {
        bufid = 5,
        components = {
          working = {
            files = {
              comp = {
                components = {
                  { name = "file", context = reviewed, lstart = 2, components = {} },
                  { name = "file", context = pending, lstart = 3, components = {} },
                },
              },
            },
          },
        },
      },
    }, { [reviewed] = true, [pending] = false }, {
      ["reviewed.lua"] = { active = 2, unresolved = 1 },
      ["pending.lua"] = { active = 1, unresolved = 0 },
    })

    assert.are.same({
      { row = 2, text = "[R 2c 1u]" },
      { row = 3, text = "[1 comment]" },
    }, marks)
  end)

  it("lists files, resolves loaded side buffers, and focuses a target path", function()
    local focused = nil
    package.loaded["commentry.diffview"] = nil
    local Diffview = require("commentry.diffview")
    local base_buf = vim.api.nvim_create_buf(false, true)
    local head_buf = vim.api.nvim_create_buf(false, true)

    local files = {
      {
        path = "a.lua",
        layout = {
          a = { file = { bufnr = base_buf } },
          b = { file = { bufnr = head_buf } },
        },
      },
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
    assert.are.same(base_buf, Diffview.file_side_buffer(view, "a.lua", "base"))
    assert.are.same(head_buf, Diffview.file_side_buffer(view, "a.lua", "head"))
    assert.is_nil(Diffview.file_side_buffer(view, "b.lua", "head"))
    assert.is_true(ok)
    assert.is_nil(err)
    assert.are.same("b.lua", focused)
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

    assert.are.same("working_tree", working_context.mode)
    assert.are.same("commit_range", revision_context.mode)
    assert.are.same(working_context.context_id, revision_context.context_id)
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

  it("ignores callable Diffview revision fields when resolving review context", function()
    package.loaded["commentry.diffview"] = nil
    local Diffview = require("commentry.diffview")

    local context = Diffview.resolve_review_context(nil, {
      root = vim.fn.getcwd(),
      left = { commit = { hash = function() end } },
      right = { commit = { hash = function() end } },
    })

    assert.are.same("working_tree", context.mode)
    assert.is_nil(context.revisions)
  end)
end)
