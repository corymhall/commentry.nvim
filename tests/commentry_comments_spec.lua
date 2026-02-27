---@module 'luassert'

local Comments = require("commentry.comments")

local function make_anchor()
  return {
    file_path = "lua/commentry/comments.lua",
    line_number = 12,
    line_side = "head",
  }
end

local function make_temp_dir()
  local path = vim.fn.tempname()
  vim.fn.mkdir(path, "p")
  return path
end

describe("commentry.comments helpers", function()
  it("builds and validates anchors", function()
    local anchor, err = Comments.build_anchor("file.lua", 5, "head")
    assert.is_nil(err)
    assert.are.same({ file_path = "file.lua", line_number = 5, line_start = 5, line_end = 5, line_side = "head" }, anchor)

    local ranged, ranged_err = Comments.build_anchor("file.lua", 5, "head", 9)
    assert.is_nil(ranged_err)
    assert.are.same(5, ranged.line_start)
    assert.are.same(9, ranged.line_end)

    local invalid, invalid_err = Comments.build_anchor("", 0, "side")
    assert.is_nil(invalid)
    assert.is_true(invalid_err:find("file_path", 1, true) ~= nil)
  end)

  it("builds anchor keys", function()
    local key, err = Comments.anchor_key(make_anchor())
    assert.is_nil(err)
    assert.are.same("lua/commentry/comments.lua|head|12-12", key)

    local invalid, invalid_err = Comments.anchor_key({})
    assert.is_nil(invalid)
    assert.is_true(invalid_err:find("file_path", 1, true) ~= nil)
  end)

  it("builds thread ids", function()
    local thread_id, err = Comments.thread_id("diff-1", make_anchor())
    assert.is_nil(err)
    assert.are.same("t-diff-1-lua/commentry/comments.lua|head|12-12", thread_id)

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
    assert.are.same(anchor.line_number, comment.line_start)
    assert.are.same(anchor.line_number, comment.line_end)
    assert.are.same(anchor.line_side, comment.line_side)
    assert.are.same("note", comment.comment_type)
    assert.are.same("Hello", comment.body)
    assert.is_true(type(comment.id) == "string" and comment.id ~= "")
    assert.is_true(comment.id:match("^c%-%w+%-%w+$") ~= nil)
    assert.is_nil(comment.id:find("e%+", 1, false))

    local updated, update_err = Comments.update_body(comment, "Updated")
    assert.is_nil(update_err)
    assert.are.same("Updated", updated.body)
    assert.are.same("note", updated.comment_type)
    assert.is_true(type(updated.updated_at) == "string" and updated.updated_at ~= "")
  end)

  it("updates draft comment type and validates choices", function()
    local anchor = make_anchor()
    local comment = assert(Comments.new_comment("diff-1", anchor, "Hello"))
    local updated, err = Comments.update_type(comment, "issue")
    assert.is_nil(err)
    assert.are.same("issue", updated.comment_type)

    local invalid, invalid_err = Comments.update_type(comment, "feedback")
    assert.is_nil(invalid)
    assert.is_true(invalid_err:find("comment_type", 1, true) ~= nil)
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
  local original_getpos
  local original_snacks
  local original_util
  local original_setreg
  local original_print

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
    original_getpos = vim.fn.getpos
    original_snacks = package.loaded["snacks"]
    original_util = package.loaded["commentry.util"]
    original_setreg = vim.fn.setreg
    original_print = _G.print
  end)

  after_each(function()
    vim.api.nvim_buf_line_count = original_buf_line_count
    vim.api.nvim_buf_get_lines = original_buf_get_lines
    vim.api.nvim_win_set_cursor = original_win_set_cursor
    vim.ui.input = original_ui_input
    vim.ui.select = original_ui_select
    vim.fn.getpos = original_getpos
    package.loaded["snacks"] = original_snacks
    package.loaded["commentry.util"] = original_util
    vim.fn.setreg = original_setreg
    _G.print = original_print
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

  it("marks blank-line anchors unresolved when current line becomes non-blank", function()
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
          body = "Blank anchor",
          line_content = "",
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
      return { "now non blank" }
    end

    comments.load_for_view({ git_root = "/tmp/project" })
    comments.render_current_buffer()

    assert.is_table(persisted)
    assert.are.same(1, #persisted.comments)
    assert.are.same("", persisted.comments[1].line_content)
    assert.are.same("unresolved", persisted.comments[1].status)
    assert.are.same(0, #persisted.threads)
  end)

  it("hydrates legacy in-range comments without line_content and keeps them active", function()
    local persisted = nil
    local captured = {}
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
        render_comment_markers = function(_, comments_to_render)
          captured = comments_to_render
        end,
      },
    })

    vim.api.nvim_buf_line_count = function()
      return 2
    end
    vim.api.nvim_buf_get_lines = function()
      return { "hydrated line" }
    end

    comments.load_for_view({ git_root = "/tmp/project" })
    comments.render_current_buffer()

    assert.is_table(persisted)
    assert.are.same(1, #persisted.comments)
    assert.are.same("hydrated line", persisted.comments[1].line_content)
    assert.is_nil(persisted.comments[1].status)
    assert.are.same(1, #persisted.threads)
    assert.are.same(1, #captured)
    assert.are.same("c1", captured[1].id)
  end)

  it("hydrates legacy in-range blank line content and persists empty string", function()
    local persisted = nil
    local captured = {}
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
          body = "Legacy blank line",
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
        render_comment_markers = function(_, comments_to_render)
          captured = comments_to_render
        end,
      },
    })

    vim.api.nvim_buf_line_count = function()
      return 2
    end
    vim.api.nvim_buf_get_lines = function()
      return { "" }
    end

    comments.load_for_view({ git_root = "/tmp/project" })
    comments.render_current_buffer()

    assert.is_table(persisted)
    assert.are.same(1, #persisted.comments)
    assert.are.same("", persisted.comments[1].line_content)
    assert.is_nil(persisted.comments[1].status)
    assert.are.same(1, #persisted.threads)
    assert.are.same(1, #captured)
    assert.are.same("c1", captured[1].id)
  end)

  it("hydrates legacy blank line content only once when unchanged", function()
    local persisted_writes = {}
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
          body = "Legacy blank line",
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
          persisted_writes[#persisted_writes + 1] = vim.deepcopy(store)
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
      return { "" }
    end

    comments.load_for_view({ git_root = "/tmp/project" })
    comments.render_current_buffer()
    comments.render_current_buffer()

    assert.are.same(1, #persisted_writes)
    assert.are.same("", persisted_writes[1].comments[1].line_content)
    assert.are.same(1, #persisted_writes[1].threads)
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
    comments._set_input_provider_for_tests(function(_, cb)
      cb(table.remove(user_inputs, 1), "note")
    end)

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

  it("keeps working-tree and commit-range contexts isolated in memory", function()
    local root = make_temp_dir()
    local working_tree_root = root .. "/working-tree"
    local commit_range_root = root .. "/commit-range"
    vim.fn.mkdir(working_tree_root, "p")
    vim.fn.mkdir(commit_range_root, "p")

    local function path_for_context(_, context_id)
      local safe = context_id:gsub("[^%w%._%-]", "_")
      return "/tmp/" .. safe .. ".json"
    end

    local stores = {
      [path_for_context("", vim.fs.normalize(vim.uv.fs_realpath(working_tree_root) or working_tree_root))] = {
        project_root = working_tree_root,
        context_id = "ctx-working-tree",
        comments = {
          {
            id = "wt-1",
            context_id = "ctx-working-tree",
            file_path = "file.lua",
            line_start = 1,
            line_end = 1,
            line_side = "head",
            comment_type = "note",
            body = "working tree comment",
            created_at = "2026-02-21T00:00:00Z",
            updated_at = "2026-02-21T00:00:00Z",
          },
        },
        threads = {
          {
            id = "t-wt-1",
            context_id = "ctx-working-tree",
            file_path = "file.lua",
            line_start = 1,
            line_end = 1,
            line_side = "head",
            comment_ids = { "wt-1" },
          },
        },
        file_reviews = {},
      },
      [path_for_context("", vim.fs.normalize(vim.uv.fs_realpath(commit_range_root) or commit_range_root))] = {
        project_root = commit_range_root,
        context_id = "ctx-commit-range",
        comments = {
          {
            id = "cr-1",
            context_id = "ctx-commit-range",
            file_path = "file.lua",
            line_start = 1,
            line_end = 1,
            line_side = "head",
            comment_type = "issue",
            body = "commit range comment",
            created_at = "2026-02-21T00:00:00Z",
            updated_at = "2026-02-21T00:00:00Z",
          },
        },
        threads = {
          {
            id = "t-cr-1",
            context_id = "ctx-commit-range",
            file_path = "file.lua",
            line_start = 1,
            line_end = 1,
            line_side = "head",
            comment_ids = { "cr-1" },
          },
        },
        file_reviews = {},
      },
    }

    local captured = {}
    local active_root = working_tree_root
    local comments = load_with_stubs({
      store = {
        path_for_context = path_for_context,
        read = function(path)
          return stores[path], nil
        end,
        write = function()
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
            view = { git_root = active_root },
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
      return { "line 1" }
    end

    comments.load_for_view({ git_root = working_tree_root })
    comments.render_current_buffer()
    assert.are.same("wt-1", captured[1].id)

    active_root = commit_range_root
    comments.load_for_view({ git_root = commit_range_root })
    comments.render_current_buffer()
    assert.are.same("cr-1", captured[1].id)

    active_root = working_tree_root
    comments.render_current_buffer()
    assert.are.same("wt-1", captured[1].id)
  end)

  it("preserves typed/range metadata and file review map when reconciling mismatches", function()
    local persisted = nil
    local root = make_temp_dir()
    local store_data = {
      project_root = root,
      context_id = "ctx-working-tree",
      comments = {
        {
          id = "c1",
          context_id = "ctx-working-tree",
          file_path = "file.lua",
          line_start = 2,
          line_end = 4,
          line_side = "head",
          comment_type = "issue",
          body = "Range comment",
          created_at = "2026-02-21T00:00:00Z",
          updated_at = "2026-02-21T00:00:00Z",
          line_content = "before",
        },
      },
      threads = {
        {
          id = "t-c1",
          context_id = "ctx-working-tree",
          file_path = "file.lua",
          line_start = 2,
          line_end = 4,
          line_side = "head",
          comment_ids = { "c1" },
        },
      },
      file_reviews = {
        ["file.lua"] = true,
        ["other.lua"] = false,
      },
    }

    local comments = load_with_stubs({
      store = {
        path_for_context = function()
          return "/tmp/project/.commentry/context.json"
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
            line_number = 2,
            line_side = "head",
            bufnr = 1,
            view = { git_root = root },
          }
        end,
        render_comment_markers = function()
          return
        end,
      },
    })

    vim.api.nvim_buf_line_count = function()
      return 10
    end
    vim.api.nvim_buf_get_lines = function()
      return { "after" }
    end

    comments.load_for_view({ git_root = root })
    comments.render_current_buffer()

    assert.is_table(persisted)
    assert.are.same(true, persisted.file_reviews["file.lua"])
    assert.are.same(false, persisted.file_reviews["other.lua"])
    assert.are.same(2, persisted.comments[1].line_start)
    assert.are.same(4, persisted.comments[1].line_end)
    assert.are.same("issue", persisted.comments[1].comment_type)
    assert.are.same("unresolved", persisted.comments[1].status)
  end)

  it("persists add/edit/delete lifecycle for a diffview context", function()
    local writes = {}
    local user_inputs = { "First line\nSecond line", "Edited body\nMore detail" }
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
    comments._set_input_provider_for_tests(function(_, cb)
      local next_value = table.remove(user_inputs, 1)
      cb(next_value, "note")
    end)
    vim.ui.select = function(items, _, cb)
      cb(items[1])
    end

    comments.add_comment()
    comments.edit_comment()
    comments.delete_comment()

    assert.are.same(3, #writes)
    assert.are.same(1, #writes[1].comments)
    assert.are.same("First line\nSecond line", writes[1].comments[1].body)
    assert.are.same("note", writes[1].comments[1].comment_type)
    assert.are.same(1, #writes[2].comments)
    assert.are.same("Edited body\nMore detail", writes[2].comments[1].body)
    assert.are.same("note", writes[2].comments[1].comment_type)
    assert.are.same(0, #writes[3].comments)
    assert.are.same(0, #writes[3].threads)
  end)

  it("creates range comments from visual line selection", function()
    local writes = {}
    local context = {
      file_path = "file.lua",
      line_number = 4,
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
    vim.fn.getpos = function(mark)
      if mark == "'<" then
        return { 1, 4, 1, 0 }
      end
      return { 1, 7, 1, 0 }
    end
    comments._set_input_provider_for_tests(function(_, cb)
      cb("Range note", "note")
    end)

    comments.add_range_comment()

    assert.are.same(1, #writes)
    assert.are.same(1, #writes[1].comments)
    assert.are.same(4, writes[1].comments[1].line_start)
    assert.are.same(7, writes[1].comments[1].line_end)
    assert.are.same(1, #writes[1].threads)
    assert.are.same(4, writes[1].threads[1].line_start)
    assert.are.same(7, writes[1].threads[1].line_end)
  end)

  it("sets selected comment type for a line comment and persists", function()
    local writes = {}
    local user_inputs = { "First" }
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
    comments._set_input_provider_for_tests(function(_, cb)
      cb(table.remove(user_inputs, 1), "note")
    end)
    vim.ui.select = function(items, opts, cb)
      if opts.prompt == "Set comment type" then
        cb("issue")
        return
      end
      cb(items[1])
    end

    comments.add_comment()
    comments.set_comment_type()

    assert.are.same(2, #writes)
    assert.are.same("note", writes[1].comments[1].comment_type)
    assert.are.same("issue", writes[2].comments[1].comment_type)
  end)

  it("targets the selected overlapping range comment for type/edit/delete", function()
    local writes = {}
    local store_data = {
      project_root = "/tmp/project",
      context_id = "ctx-working-tree",
      comments = {
        {
          id = "c1",
          context_id = "ctx-working-tree",
          file_path = "file.lua",
          line_start = 4,
          line_end = 6,
          line_side = "head",
          comment_type = "note",
          body = "first range",
          created_at = "2026-02-21T00:00:00Z",
          updated_at = "2026-02-21T00:00:00Z",
        },
        {
          id = "c2",
          context_id = "ctx-working-tree",
          file_path = "file.lua",
          line_start = 5,
          line_end = 7,
          line_side = "head",
          comment_type = "suggestion",
          body = "second range",
          created_at = "2026-02-21T00:00:01Z",
          updated_at = "2026-02-21T00:00:01Z",
        },
      },
      threads = {
        {
          id = "t-c1",
          context_id = "ctx-working-tree",
          file_path = "file.lua",
          line_start = 4,
          line_end = 6,
          line_side = "head",
          comment_ids = { "c1" },
        },
        {
          id = "t-c2",
          context_id = "ctx-working-tree",
          file_path = "file.lua",
          line_start = 5,
          line_end = 7,
          line_side = "head",
          comment_ids = { "c2" },
        },
      },
      file_reviews = {},
    }

    local context = {
      file_path = "file.lua",
      line_number = 5,
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
          return store_data
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
      return 50
    end
    vim.api.nvim_buf_get_lines = function()
      return { "line text" }
    end
    comments._set_input_provider_for_tests(function(opts, cb)
      if opts.title == "Edit comment" then
        cb("edited second range", "issue")
        return
      end
      cb(nil, nil)
    end)
    vim.ui.select = function(items, opts, cb)
      if opts.prompt == "Set comment type" and type(items[1]) == "string" then
        cb("issue")
        return
      end
      cb(items[2])
    end

    comments.load_for_view(context.view)
    comments.set_comment_type()
    comments.edit_comment()
    comments.delete_comment()

    assert.are.same(4, #writes)
    assert.are.same("note", writes[2].comments[1].comment_type)
    assert.are.same("issue", writes[2].comments[2].comment_type)
    assert.are.same("edited second range", writes[3].comments[2].body)
    assert.are.same(1, #writes[4].comments)
    assert.are.same("c1", writes[4].comments[1].id)
    assert.are.same(1, #writes[4].threads)
    assert.are.same("t-c1", writes[4].threads[1].id)
  end)

  it("requires explicit review context for range/type/export operations", function()
    local writes = {}
    local selects = 0
    local context = {
      file_path = "file.lua",
      line_number = 4,
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
        resolve_review_context = function()
          return nil, "context_id_unavailable"
        end,
        current_file_context = function()
          return context
        end,
        render_comment_markers = function()
          return
        end,
      },
    })

    vim.api.nvim_buf_line_count = function()
      return 10
    end
    vim.api.nvim_buf_get_lines = function()
      return { "line text" }
    end
    vim.fn.getpos = function(mark)
      if mark == "'<" then
        return { 1, 4, 1, 0 }
      end
      return { 1, 6, 1, 0 }
    end
    comments._set_input_provider_for_tests(function(_, cb)
      cb("range note", "note")
    end)
    vim.ui.select = function(_, _, cb)
      selects = selects + 1
      cb(nil)
    end

    comments.add_range_comment()
    comments.set_comment_type()
    local markdown, export_err = comments.generate_export_markdown({ view = context.view })

    assert.are.same(0, #writes)
    assert.are.same(0, selects)
    assert.is_nil(markdown)
    assert.are.same("context_id_unavailable", export_err)
  end)

  it("toggles file reviewed state and persists indicator state", function()
    local writes = {}
    local indicator = {}
    local context = {
      file_path = "file.lua",
      line_number = 1,
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
            context_id = "ctx-working-tree",
            comments = {},
            threads = {},
            file_reviews = {
              ["file.lua"] = false,
              ["other.lua"] = true,
            },
          }
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
        render_file_review_indicator = function(_, reviewed)
          indicator[#indicator + 1] = reviewed
        end,
      },
    })

    vim.api.nvim_buf_line_count = function()
      return 10
    end

    comments.load_for_view(context.view)
    local initial_reviewed = comments.current_file_reviewed()
    comments.toggle_file_reviewed()
    local reviewed_after_toggle = comments.current_file_reviewed()
    comments.toggle_file_reviewed()
    local reviewed_after_second_toggle = comments.current_file_reviewed()

    assert.is_false(initial_reviewed)
    assert.is_true(reviewed_after_toggle)
    assert.is_false(reviewed_after_second_toggle)
    assert.are.same(2, #writes)
    assert.are.same(true, writes[1].file_reviews["file.lua"])
    assert.are.same(false, writes[2].file_reviews["file.lua"])
    assert.are.same({ true, false }, indicator)
  end)

  it("jumps to next unreviewed file in diffview order", function()
    local focused_path = nil
    local context = {
      file_path = "file.lua",
      line_number = 1,
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
            context_id = "ctx-working-tree",
            comments = {},
            threads = {},
            file_reviews = {
              ["file.lua"] = true,
              ["other.lua"] = false,
              ["third.lua"] = true,
            },
          }
        end,
        write = function()
          return true
        end,
      },
      diffview = {
        current_file_context = function()
          return context
        end,
        list_view_files = function()
          return { "file.lua", "other.lua", "third.lua" }
        end,
        focus_file = function(_, path)
          focused_path = path
          return true, nil
        end,
        render_comment_markers = function()
          return
        end,
      },
    })

    vim.api.nvim_buf_line_count = function()
      return 10
    end

    comments.load_for_view(context.view)
    comments.next_unreviewed_file()

    assert.are.same("other.lua", focused_path)
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
              {
                id = "c2",
                diff_id = "/tmp/project",
                file_path = "other.lua",
                line_number = 8,
                line_side = "head",
                body = "other file draft",
                line_content = "other line",
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
              {
                id = "t-/tmp/project-other.lua|head|8",
                diff_id = "/tmp/project",
                file_path = "other.lua",
                line_number = 8,
                line_side = "head",
                comment_ids = { "c2" },
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
    assert.is_true(type(captured_opts.format_item) == "function")
    local label = captured_opts.format_item(captured_items[1])
    assert.is_true(label:find("file.lua @ head:L4", 1, true) ~= nil)
    assert.is_true(label:find("[note]", 1, true) ~= nil)
    assert.is_true(label:find("first draft", 1, true) ~= nil)
    assert.are.same({ 4, 0 }, moved_cursor)
  end)

  it("generates deterministic export markdown with typed range labels", function()
    local root = vim.fs.normalize(vim.fn.getcwd())
    local comments = load_with_stubs({
      store = {
        path_for_context = function()
          return "/tmp/project/.commentry/contexts/export/commentry.json"
        end,
        read = function()
          return {
            project_root = root,
            context_id = root,
            comments = {
              {
                id = "c3",
                context_id = root,
                file_path = "a.lua",
                line_start = 2,
                line_end = 4,
                line_side = "head",
                comment_type = "issue",
                body = "Range issue",
                created_at = "2026-02-21T00:00:03Z",
                updated_at = "2026-02-21T00:00:03Z",
              },
              {
                id = "c1",
                context_id = root,
                file_path = "a.lua",
                line_start = 1,
                line_end = 1,
                line_side = "base",
                comment_type = "note",
                body = "Base note",
                created_at = "2026-02-21T00:00:01Z",
                updated_at = "2026-02-21T00:00:01Z",
              },
              {
                id = "c2",
                context_id = root,
                file_path = "z.lua",
                line_start = 7,
                line_end = 7,
                line_side = "head",
                comment_type = "suggestion",
                body = "First line\nSecond line",
                created_at = "2026-02-21T00:00:02Z",
                updated_at = "2026-02-21T00:00:02Z",
              },
              {
                id = "c4",
                context_id = root,
                file_path = "z.lua",
                line_start = 8,
                line_end = 8,
                line_side = "head",
                comment_type = "issue",
                body = "Hidden unresolved",
                status = "unresolved",
                created_at = "2026-02-21T00:00:04Z",
                updated_at = "2026-02-21T00:00:04Z",
              },
            },
            threads = {},
          }
        end,
        write = function()
          return true
        end,
      },
      diffview = {
        get_current_view = function()
          return { git_root = root }
        end,
        current_file_context = function()
          return {
            file_path = "a.lua",
            line_number = 1,
            line_side = "head",
            bufnr = 1,
            view = { git_root = root },
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

    local ok = comments.load_for_view({ git_root = root })
    assert.is_true(ok)

    local markdown, err = comments.generate_export_markdown()
    assert.is_nil(err)
    assert.is_true(type(markdown) == "string" and markdown ~= "")
    assert.is_true(markdown:find("# Commentry Draft Export", 1, true) ~= nil)
    assert.is_true(markdown:find("- Comments: 3", 1, true) ~= nil)
    assert.is_true(markdown:find("## `a.lua`", 1, true) ~= nil)
    assert.is_true(markdown:find("## `z.lua`", 1, true) ~= nil)
    assert.is_true(markdown:find("%[note%] `base:L1`") ~= nil)
    assert.is_true(markdown:find("%[issue%] `head:L2%-L4`") ~= nil)
    assert.is_true(markdown:find("%[suggestion%] `head:L7`") ~= nil)
    assert.is_true(markdown:find("Hidden unresolved", 1, true) == nil)

    local first = markdown:find("%[note%] `base:L1`")
    local second = markdown:find("%[issue%] `head:L2%-L4`")
    local third = markdown:find("%[suggestion%] `head:L7`")
    assert.is_true(first < second and second < third)
  end)

  it("exports markdown to register destination", function()
    local root = vim.fs.normalize(vim.fn.getcwd())
    local setreg_calls = {}
    local infos = {}

    package.loaded["commentry.util"] = {
      error = function(msg)
        error(msg)
      end,
      warn = function()
        return
      end,
      info = function(msg)
        infos[#infos + 1] = msg
      end,
      debug = function()
        return
      end,
    }
    vim.fn.setreg = function(register, value)
      setreg_calls[#setreg_calls + 1] = { register = register, value = value }
    end

    local comments = load_with_stubs({
      store = {
        path_for_context = function()
          return "/tmp/project/.commentry/contexts/export/commentry.json"
        end,
        read = function()
          return {
            project_root = root,
            context_id = root,
            comments = {
              {
                id = "c1",
                context_id = root,
                file_path = "file.lua",
                line_start = 3,
                line_end = 3,
                line_side = "head",
                comment_type = "note",
                body = "Hello",
                created_at = "2026-02-21T00:00:01Z",
                updated_at = "2026-02-21T00:00:01Z",
              },
            },
            threads = {},
          }
        end,
        write = function()
          return true
        end,
      },
      diffview = {
        get_current_view = function()
          return { git_root = root }
        end,
        current_file_context = function()
          return {
            file_path = "file.lua",
            line_number = 3,
            line_side = "head",
            bufnr = 1,
            view = { git_root = root },
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

    comments.load_for_view({ git_root = root })
    comments.export_comments("register:a")

    assert.are.same(1, #setreg_calls)
    assert.are.same("a", setreg_calls[1].register)
    assert.is_true(setreg_calls[1].value:find("# Commentry Draft Export", 1, true) ~= nil)
    assert.are.same("Exported draft comments to register `a`", infos[1])
  end)

  it("reports when no jumpable comments exist for current context", function()
    local infos = {}
    package.loaded["commentry.util"] = {
      error = function()
        return
      end,
      warn = function()
        return
      end,
      info = function(msg)
        infos[#infos + 1] = msg
      end,
      debug = function()
        return
      end,
    }
    package.loaded["snacks"] = {
      picker = {
        select = function()
          error("picker should not be called")
        end,
      },
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
            comments = {
              {
                id = "c2",
                diff_id = "/tmp/project",
                file_path = "other.lua",
                line_number = 8,
                line_side = "head",
                body = "other file draft",
              },
            },
            threads = {
              {
                id = "t-/tmp/project-other.lua|head|8",
                diff_id = "/tmp/project",
                file_path = "other.lua",
                line_number = 8,
                line_side = "head",
                comment_ids = { "c2" },
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

    comments.load_for_view({ git_root = "/tmp/project" })
    comments.list_comments()
    assert.are.same("No jumpable draft comments for current diff file/side", infos[1])
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

  it("does not warn when render runs in diffview non-file windows", function()
    local warned = 0
    package.loaded["commentry.util"] = {
      info = function() end,
      error = function() end,
      warn = function()
        warned = warned + 1
      end,
      debug = function() end,
    }

    local comments = load_with_stubs({
      store = {
        read = function()
          return nil, "not_found"
        end,
        write = function()
          return true
        end,
      },
      diffview = {
        current_file_context = function()
          return nil, "current buffer is not a diffview file buffer"
        end,
      },
    })

    comments.render_current_buffer()
    assert.are.same(0, warned)
  end)
end)
