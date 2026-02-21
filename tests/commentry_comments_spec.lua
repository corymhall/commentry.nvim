---@module 'luassert'

local Comments = require("commentry.comments")

local function make_anchor()
  return {
    file_path = "lua/commentry/comments.lua",
    line_number = 12,
    line_side = "head",
  }
end

describe("commentry.comments helpers", function()
  it("builds and validates anchors", function()
    local anchor, err = Comments.build_anchor("file.lua", 5, "head")
    assert.is_nil(err)
    assert.are.same({ file_path = "file.lua", line_number = 5, line_side = "head" }, anchor)

    local invalid, invalid_err = Comments.build_anchor("", 0, "side")
    assert.is_nil(invalid)
    assert.is_true(invalid_err:find("file_path", 1, true) ~= nil)
  end)

  it("builds anchor keys", function()
    local key, err = Comments.anchor_key(make_anchor())
    assert.is_nil(err)
    assert.are.same("lua/commentry/comments.lua|head|12", key)

    local invalid, invalid_err = Comments.anchor_key({})
    assert.is_nil(invalid)
    assert.is_true(invalid_err:find("file_path", 1, true) ~= nil)
  end)

  it("builds thread ids", function()
    local thread_id, err = Comments.thread_id("diff-1", make_anchor())
    assert.is_nil(err)
    assert.are.same("t-diff-1-lua/commentry/comments.lua|head|12", thread_id)

    local invalid, invalid_err = Comments.thread_id("", make_anchor())
    assert.is_nil(invalid)
    assert.are.same("diff_id is required", invalid_err)
  end)

  it("creates and updates draft comments", function()
    local anchor = make_anchor()
    local comment, err = Comments.new_comment("diff-1", anchor, "Hello")
    assert.is_nil(err)
    assert.are.same("diff-1", comment.diff_id)
    assert.are.same(anchor.file_path, comment.file_path)
    assert.are.same(anchor.line_number, comment.line_number)
    assert.are.same(anchor.line_side, comment.line_side)
    assert.are.same("Hello", comment.body)
    assert.is_true(type(comment.id) == "string" and comment.id ~= "")

    local updated, update_err = Comments.update_body(comment, "Updated")
    assert.is_nil(update_err)
    assert.are.same("Updated", updated.body)
    assert.is_true(type(updated.updated_at) == "string" and updated.updated_at ~= "")
  end)

  it("creates threads with default comment ids", function()
    local anchor = make_anchor()
    local thread, err = Comments.new_thread("diff-1", anchor)
    assert.is_nil(err)
    assert.are.same("diff-1", thread.diff_id)
    assert.are.same(anchor.file_path, thread.file_path)
    assert.are.same(anchor.line_side, thread.line_side)
    assert.are.same({}, thread.comment_ids)
  end)
end)

describe("commentry.comments persistence", function()
  local original_store
  local original_diffview
  local original_comments
  local original_buf_line_count
  local original_buf_get_lines
  local original_win_set_cursor
  local original_ui_input
  local original_ui_select
  local original_snacks
  local original_util

  local function load_with_stubs(stubs)
    original_store = package.loaded["commentry.store"]
    original_diffview = package.loaded["commentry.diffview"]
    original_comments = package.loaded["commentry.comments"]

    package.loaded["commentry.store"] = stubs.store
    package.loaded["commentry.diffview"] = stubs.diffview
    package.loaded["commentry.comments"] = nil

    return require("commentry.comments")
  end

  before_each(function()
    original_buf_line_count = vim.api.nvim_buf_line_count
    original_buf_get_lines = vim.api.nvim_buf_get_lines
    original_win_set_cursor = vim.api.nvim_win_set_cursor
    original_ui_input = vim.ui.input
    original_ui_select = vim.ui.select
    original_snacks = package.loaded["snacks"]
    original_util = package.loaded["commentry.util"]
  end)

  after_each(function()
    vim.api.nvim_buf_line_count = original_buf_line_count
    vim.api.nvim_buf_get_lines = original_buf_get_lines
    vim.api.nvim_win_set_cursor = original_win_set_cursor
    vim.ui.input = original_ui_input
    vim.ui.select = original_ui_select
    package.loaded["snacks"] = original_snacks
    package.loaded["commentry.util"] = original_util
    package.loaded["commentry.store"] = original_store
    package.loaded["commentry.diffview"] = original_diffview
    package.loaded["commentry.comments"] = original_comments
  end)

  it("loads stored comments for a view", function()
    local captured = {}
    local store_data = {
      project_root = "/tmp/project",
      diff_id = "/tmp/project",
      comments = {
        {
          id = "c1",
          diff_id = "/tmp/project",
          file_path = "file.lua",
          line_number = 3,
          line_side = "head",
          body = "Persisted",
          line_content = "persisted line",
        },
      },
      threads = {
        {
          id = "t-/tmp/project-file.lua|head|3",
          diff_id = "/tmp/project",
          file_path = "file.lua",
          line_number = 3,
          line_side = "head",
          comment_ids = { "c1" },
        },
      },
    }

    local comments = load_with_stubs({
      store = {
        path_for_project = function()
          return "/tmp/project/.commentry/commentry.json"
        end,
        read = function()
          return store_data
        end,
        write = function()
          return true
        end,
      },
      diffview = {
        current_file_context = function()
          return {
            file_path = "file.lua",
            line_number = 3,
            line_side = "head",
            bufnr = 1,
            view = { git_root = "/tmp/project" },
          }
        end,
        render_comment_markers = function(_, comments_to_render)
          captured = comments_to_render
        end,
      },
    })

    vim.api.nvim_buf_line_count = function()
      return 10
    end
    vim.api.nvim_buf_get_lines = function()
      return { "persisted line" }
    end

    local ok = comments.load_for_view({ git_root = "/tmp/project" })
    assert.is_true(ok)
    comments.render_current_buffer()
    assert.are.same(1, #captured)
    assert.are.same("c1", captured[1].id)
  end)

  it("reconciles comments beyond buffer length and persists", function()
    local persisted = nil
    local store_data = {
      project_root = "/tmp/project",
      diff_id = "/tmp/project",
      comments = {
        {
          id = "c1",
          diff_id = "/tmp/project",
          file_path = "file.lua",
          line_number = 5,
          line_side = "head",
          body = "Out of range",
        },
      },
      threads = {
        {
          id = "t-/tmp/project-file.lua|head|5",
          diff_id = "/tmp/project",
          file_path = "file.lua",
          line_number = 5,
          line_side = "head",
          comment_ids = { "c1" },
        },
      },
    }

    local comments = load_with_stubs({
      store = {
        path_for_project = function()
          return "/tmp/project/.commentry/commentry.json"
        end,
        read = function()
          return store_data
        end,
        write = function(_, store)
          persisted = store
          return true
        end,
      },
      diffview = {
        current_file_context = function()
          return {
            file_path = "file.lua",
            line_number = 1,
            line_side = "head",
            bufnr = 1,
            view = { git_root = "/tmp/project" },
          }
        end,
        render_comment_markers = function()
          return
        end,
      },
    })

    vim.api.nvim_buf_line_count = function()
      return 1
    end

    comments.load_for_view({ git_root = "/tmp/project" })
    comments.render_current_buffer()

    assert.is_table(persisted)
    assert.are.same(1, #persisted.comments)
    assert.are.same("unresolved", persisted.comments[1].status)
    assert.are.same(0, #persisted.threads)
  end)

  it("marks in-range mismatched line content unresolved and persists", function()
    local persisted = nil
    local store_data = {
      project_root = "/tmp/project",
      diff_id = "/tmp/project",
      comments = {
        {
          id = "c1",
          diff_id = "/tmp/project",
          file_path = "file.lua",
          line_number = 1,
          line_side = "head",
          body = "Anchor changed",
          line_content = "before",
        },
      },
      threads = {
        {
          id = "t-/tmp/project-file.lua|head|1",
          diff_id = "/tmp/project",
          file_path = "file.lua",
          line_number = 1,
          line_side = "head",
          comment_ids = { "c1" },
        },
      },
    }

    local comments = load_with_stubs({
      store = {
        path_for_project = function()
          return "/tmp/project/.commentry/commentry.json"
        end,
        read = function()
          return store_data
        end,
        write = function(_, store)
          persisted = store
          return true
        end,
      },
      diffview = {
        current_file_context = function()
          return {
            file_path = "file.lua",
            line_number = 1,
            line_side = "head",
            bufnr = 1,
            view = { git_root = "/tmp/project" },
          }
        end,
        render_comment_markers = function()
          return
        end,
      },
    })

    vim.api.nvim_buf_line_count = function()
      return 2
    end
    vim.api.nvim_buf_get_lines = function()
      return { "after" }
    end

    comments.load_for_view({ git_root = "/tmp/project" })
    comments.render_current_buffer()

    assert.is_table(persisted)
    assert.are.same(1, #persisted.comments)
    assert.are.same("unresolved", persisted.comments[1].status)
    assert.are.same(0, #persisted.threads)
  end)

  it("marks legacy in-range comments without line_content unresolved", function()
    local persisted = nil
    local store_data = {
      project_root = "/tmp/project",
      diff_id = "/tmp/project",
      comments = {
        {
          id = "c1",
          diff_id = "/tmp/project",
          file_path = "file.lua",
          line_number = 1,
          line_side = "head",
          body = "Legacy anchor",
        },
      },
      threads = {
        {
          id = "t-/tmp/project-file.lua|head|1",
          diff_id = "/tmp/project",
          file_path = "file.lua",
          line_number = 1,
          line_side = "head",
          comment_ids = { "c1" },
        },
      },
    }

    local comments = load_with_stubs({
      store = {
        path_for_project = function()
          return "/tmp/project/.commentry/commentry.json"
        end,
        read = function()
          return store_data
        end,
        write = function(_, store)
          persisted = store
          return true
        end,
      },
      diffview = {
        current_file_context = function()
          return {
            file_path = "file.lua",
            line_number = 1,
            line_side = "head",
            bufnr = 1,
            view = { git_root = "/tmp/project" },
          }
        end,
        render_comment_markers = function()
          return
        end,
      },
    })

    vim.api.nvim_buf_line_count = function()
      return 2
    end

    comments.load_for_view({ git_root = "/tmp/project" })
    comments.render_current_buffer()

    assert.is_table(persisted)
    assert.are.same(1, #persisted.comments)
    assert.are.same("unresolved", persisted.comments[1].status)
    assert.are.same(0, #persisted.threads)
  end)

  it("keeps dirty in-memory edits when persist fails and load is retriggered", function()
    local captured = {}
    local writes = 0
    local user_inputs = { "Dirty comment" }
    local context = {
      file_path = "file.lua",
      line_number = 2,
      line_side = "head",
      bufnr = 1,
      view = { git_root = "/tmp/project" },
    }

    local comments = load_with_stubs({
      store = {
        path_for_project = function()
          return "/tmp/project/.commentry/commentry.json"
        end,
        read = function()
          return {
            project_root = "/tmp/project",
            diff_id = "/tmp/project",
            comments = {},
            threads = {},
          }
        end,
        write = function()
          writes = writes + 1
          return false, "write_failed"
        end,
      },
      diffview = {
        current_file_context = function()
          return context
        end,
        render_comment_markers = function(_, comments_to_render)
          captured = comments_to_render
        end,
      },
    })

    vim.api.nvim_buf_line_count = function()
      return 10
    end
    vim.api.nvim_buf_get_lines = function()
      return { "line text" }
    end
    vim.ui.input = function(_, cb)
      cb(table.remove(user_inputs, 1))
    end

    comments.add_comment()
    assert.are.same(1, writes)
    assert.are.same(1, #captured)

    local loaded = comments.load_for_view({ git_root = "/tmp/project" })
    assert.is_false(loaded)
    comments.render_current_buffer()
    assert.are.same(1, #captured)
    assert.are.same("Dirty comment", captured[1].body)
  end)

  it("resolves project root when view git_root points at .git", function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.git", "p")
    local expected_root = vim.fs.normalize(vim.uv.fs_realpath(root) or root)
    local received_root = nil
    local comments = load_with_stubs({
      store = {
        path_for_project = function(root)
          received_root = root
          return "/tmp/project/.commentry/commentry.json"
        end,
        read = function()
          return {
            project_root = "/tmp/project",
            diff_id = "/tmp/project",
            comments = {},
            threads = {},
          }
        end,
        write = function()
          return true
        end,
      },
      diffview = {
        current_file_context = function()
          return nil, "unused"
        end,
        render_comment_markers = function()
          return
        end,
      },
    })

    local ok = comments.load_for_view({ git_root = root .. "/.git" })
    assert.is_true(ok)
    assert.are.same(expected_root, received_root)
  end)

  it("persists add/edit/delete lifecycle for a diffview context", function()
    local writes = {}
    local user_inputs = { "First", "Edited body" }
    local context = {
      file_path = "file.lua",
      line_number = 3,
      line_side = "head",
      bufnr = 1,
      view = { git_root = "/tmp/project" },
    }

    local comments = load_with_stubs({
      store = {
        path_for_project = function()
          return "/tmp/project/.commentry/commentry.json"
        end,
        read = function()
          return nil, "not_found"
        end,
        write = function(_, store)
          writes[#writes + 1] = vim.deepcopy(store)
          return true
        end,
      },
      diffview = {
        current_file_context = function()
          return context
        end,
        render_comment_markers = function()
          return
        end,
      },
    })

    vim.api.nvim_buf_line_count = function()
      return 30
    end
    vim.api.nvim_buf_get_lines = function()
      return { "line text" }
    end
    vim.ui.input = function(_, cb)
      local next_value = table.remove(user_inputs, 1)
      cb(next_value)
    end
    vim.ui.select = function(items, _, cb)
      cb(items[1])
    end

    comments.add_comment()
    comments.edit_comment()
    comments.delete_comment()

    assert.are.same(3, #writes)
    assert.are.same(1, #writes[1].comments)
    assert.are.same("First", writes[1].comments[1].body)
    assert.are.same(1, #writes[2].comments)
    assert.are.same("Edited body", writes[2].comments[1].body)
    assert.are.same(0, #writes[3].comments)
    assert.are.same(0, #writes[3].threads)
  end)

  it("lists draft comments and jumps to selected entry line", function()
    local moved_cursor = nil
    local captured_items = nil
    local captured_opts = nil

    local comments = load_with_stubs({
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
                line_number = 4,
                line_side = "head",
                body = "first draft",
                line_content = "line four",
              },
            },
            threads = {
              {
                id = "t-/tmp/project-file.lua|head|4",
                diff_id = "/tmp/project",
                file_path = "file.lua",
                line_number = 4,
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
        get_current_view = function()
          return { git_root = "/tmp/project" }
        end,
        current_file_context = function()
          return {
            file_path = "file.lua",
            line_number = 1,
            line_side = "head",
            bufnr = 1,
            view = { git_root = "/tmp/project" },
          }
        end,
        render_comment_markers = function()
          return
        end,
        render_hover_preview = function()
          return
        end,
        clear_hover_preview = function()
          return
        end,
      },
    })

    package.loaded["snacks"] = {
      picker = {
        select = function(items, opts, cb)
          captured_items = items
          captured_opts = opts
          cb(items[1])
        end,
      },
    }
    vim.api.nvim_win_set_cursor = function(_, pos)
      moved_cursor = pos
    end

    comments.load_for_view({ git_root = "/tmp/project" })
    comments.list_comments()

    assert.is_table(captured_items)
    assert.are.same(1, #captured_items)
    assert.are.same("c1", captured_items[1].id)
    assert.are.same("Commentry draft comments", captured_opts.prompt)
    assert.are.same({ 4, 0 }, moved_cursor)
  end)

  it("errors when snacks dependency is unavailable for list-comments", function()
    local errors = {}
    package.loaded["commentry.util"] = {
      error = function(msg)
        errors[#errors + 1] = msg
      end,
      warn = function()
        return
      end,
      info = function()
        return
      end,
      debug = function()
        return
      end,
    }
    package.loaded["snacks"] = nil

    local comments = load_with_stubs({
      store = {
        path_for_project = function()
          return "/tmp/project/.commentry/commentry.json"
        end,
        read = function()
          return nil, "not_found"
        end,
        write = function()
          return true
        end,
      },
      diffview = {
        get_current_view = function()
          return { git_root = "/tmp/project" }
        end,
        current_file_context = function()
          return {
            file_path = "file.lua",
            line_number = 1,
            line_side = "head",
            bufnr = 1,
            view = { git_root = "/tmp/project" },
          }
        end,
        render_comment_markers = function()
          return
        end,
        render_hover_preview = function()
          return
        end,
        clear_hover_preview = function()
          return
        end,
      },
    })

    comments.list_comments()
    assert.are.same("snacks.nvim is required for :Commentry list-comments", errors[1])
  end)
end)
