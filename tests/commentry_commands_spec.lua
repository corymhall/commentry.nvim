---@module 'luassert'

describe("commentry lifecycle hooks", function()
  local original_diffview
  local original_diffview_lib
  local original_comments
  local original_config
  local original_create_autocmd
  local original_schedule

  before_each(function()
    original_diffview = package.loaded["commentry.diffview"]
    original_diffview_lib = package.loaded["diffview.lib"]
    original_comments = package.loaded["commentry.comments"]
    original_config = package.loaded["commentry.config"]
    original_create_autocmd = vim.api.nvim_create_autocmd
    original_schedule = vim.schedule
  end)

  after_each(function()
    package.loaded["commentry.diffview"] = original_diffview
    package.loaded["diffview.lib"] = original_diffview_lib
    package.loaded["commentry.comments"] = original_comments
    package.loaded["commentry.config"] = original_config
    vim.api.nvim_create_autocmd = original_create_autocmd
    vim.schedule = original_schedule
  end)

  it("loads persisted comments when diffview auto-attach events fire", function()
    local autocmds = {}
    local calls = { load = 0, render = 0 }

    vim.api.nvim_create_autocmd = function(_, opts)
      autocmds[#autocmds + 1] = opts
    end
    vim.schedule = function(cb)
      cb()
    end

    package.loaded["commentry.config"] = {
      augroup = 1,
      diffview = { auto_attach = true },
    }
    package.loaded["commentry.comments"] = {
      load_current_view = function()
        calls.load = calls.load + 1
        return true
      end,
      render_current_buffer = function()
        calls.render = calls.render + 1
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

    assert.are.same(2, #autocmds)
    autocmds[1].callback()
    autocmds[2].callback()

    assert.are.same(2, calls.load)
    assert.are.same(2, calls.render)
  end)
end)

describe("commentry command routing", function()
  local original_comments
  local original_config
  local original_diffview
  local original_commands
  local original_create_autocmd
  local original_util
  local original_orchestrator
  local original_codex_preload

  before_each(function()
    original_comments = package.loaded["commentry.comments"]
    original_config = package.loaded["commentry.config"]
    original_diffview = package.loaded["commentry.diffview"]
    original_commands = package.loaded["commentry.commands"]
    original_create_autocmd = vim.api.nvim_create_autocmd
    original_util = package.loaded["commentry.util"]
    original_orchestrator = package.loaded["commentry.codex.orchestrator"]
    original_codex_preload = package.preload["commentry.codex"]
  end)

  after_each(function()
    package.loaded["commentry.comments"] = original_comments
    package.loaded["commentry.config"] = original_config
    package.loaded["commentry.diffview"] = original_diffview
    package.loaded["commentry.commands"] = original_commands
    package.loaded["commentry.util"] = original_util
    package.loaded["commentry.codex.orchestrator"] = original_orchestrator
    vim.api.nvim_create_autocmd = original_create_autocmd
    package.preload["commentry.codex"] = original_codex_preload
  end)

  it("routes :Commentry list-comments to comments.list_comments", function()
    local called = 0
    vim.api.nvim_create_autocmd = function()
      return 1
    end

    package.loaded["commentry.comments"] = {
      list_comments = function()
        called = called + 1
      end,
      set_comment_type = function()
        return
      end,
      export_comments = function()
        return
      end,
      render_current_buffer = function()
        return
      end,
    }
    package.loaded["commentry.config"] = {
      augroup = 1,
      diffview = { enabled = true },
      keymaps = { add_comment = "mc", edit_comment = "me", delete_comment = "md", set_comment_type = "mt" },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    Commands.cmd({ args = "list-comments" })

    assert.are.same(1, called)
  end)

  it("includes list-comments in command completion", function()
    vim.api.nvim_create_autocmd = function()
      return 1
    end
    package.loaded["commentry.comments"] = {
      list_comments = function()
        return
      end,
      set_comment_type = function()
        return
      end,
      export_comments = function()
        return
      end,
      render_current_buffer = function()
        return
      end,
    }
    package.loaded["commentry.config"] = {
      augroup = 1,
      diffview = { enabled = true },
      keymaps = { add_comment = "mc", edit_comment = "me", delete_comment = "md", set_comment_type = "mt" },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    local matches = Commands.complete("Commentry list")

    assert.is_true(vim.tbl_contains(matches, "list-comments"))
  end)

  it("includes export in command completion", function()
    vim.api.nvim_create_autocmd = function()
      return 1
    end
    package.loaded["commentry.comments"] = {
      list_comments = function()
        return
      end,
      set_comment_type = function()
        return
      end,
      export_comments = function()
        return
      end,
      render_current_buffer = function()
        return
      end,
    }
    package.loaded["commentry.config"] = {
      augroup = 1,
      diffview = { enabled = true },
      keymaps = { add_comment = "mc", edit_comment = "me", delete_comment = "md", set_comment_type = "mt" },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    local matches = Commands.complete("Commentry ex")

    assert.is_true(vim.tbl_contains(matches, "export"))
  end)

  it("includes send-to-codex in command completion", function()
    vim.api.nvim_create_autocmd = function()
      return 1
    end
    package.loaded["commentry.comments"] = {
      list_comments = function()
        return
      end,
      set_comment_type = function()
        return
      end,
      export_comments = function()
        return
      end,
      render_current_buffer = function()
        return
      end,
    }
    package.loaded["commentry.config"] = {
      augroup = 1,
      codex = { enabled = true },
      diffview = { enabled = true },
      keymaps = { add_comment = "mc", edit_comment = "me", delete_comment = "md", set_comment_type = "mt" },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    local matches = Commands.complete("Commentry send")

    assert.is_true(vim.tbl_contains(matches, "send-to-codex"))
  end)

  it("keeps existing command completion unaffected when codex is disabled", function()
    vim.api.nvim_create_autocmd = function()
      return 1
    end
    package.preload["commentry.codex"] = function()
      error("codex namespace should not load from command setup when disabled")
    end
    package.loaded["commentry.comments"] = {
      list_comments = function()
        return
      end,
      set_comment_type = function()
        return
      end,
      export_comments = function()
        return
      end,
      render_current_buffer = function()
        return
      end,
    }
    package.loaded["commentry.config"] = {
      augroup = 1,
      codex = { enabled = false },
      diffview = { enabled = true },
      keymaps = { add_comment = "mc", edit_comment = "me", delete_comment = "md", set_comment_type = "mt" },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    local matches = Commands.complete("Commentry ")

    assert.is_true(vim.tbl_contains(matches, "list-comments"))
    assert.is_true(vim.tbl_contains(matches, "export"))
  end)

  it("routes :Commentry set-comment-type to comments.set_comment_type", function()
    local called = 0
    vim.api.nvim_create_autocmd = function()
      return 1
    end

    package.loaded["commentry.comments"] = {
      list_comments = function()
        return
      end,
      set_comment_type = function()
        called = called + 1
      end,
      export_comments = function()
        return
      end,
      render_current_buffer = function()
        return
      end,
    }
    package.loaded["commentry.config"] = {
      augroup = 1,
      diffview = { enabled = true },
      keymaps = { add_comment = "mc", edit_comment = "me", delete_comment = "md", set_comment_type = "mt" },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    Commands.cmd({ args = "set-comment-type" })

    assert.are.same(1, called)
  end)

  it("routes :Commentry toggle-file-reviewed to comments.toggle_file_reviewed", function()
    local called = 0
    vim.api.nvim_create_autocmd = function()
      return 1
    end

    package.loaded["commentry.comments"] = {
      list_comments = function()
        return
      end,
      set_comment_type = function()
        return
      end,
      toggle_file_reviewed = function()
        called = called + 1
      end,
      next_unreviewed_file = function()
        return
      end,
      export_comments = function()
        return
      end,
      render_current_buffer = function()
        return
      end,
    }
    package.loaded["commentry.config"] = {
      augroup = 1,
      diffview = { enabled = true },
      keymaps = { add_comment = "mc", edit_comment = "me", delete_comment = "md", set_comment_type = "mt" },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    Commands.cmd({ args = "toggle-file-reviewed" })

    assert.are.same(1, called)
  end)

  it("routes :Commentry next-unreviewed to comments.next_unreviewed_file", function()
    local called = 0
    vim.api.nvim_create_autocmd = function()
      return 1
    end

    package.loaded["commentry.comments"] = {
      list_comments = function()
        return
      end,
      set_comment_type = function()
        return
      end,
      toggle_file_reviewed = function()
        return
      end,
      next_unreviewed_file = function()
        called = called + 1
      end,
      export_comments = function()
        return
      end,
      render_current_buffer = function()
        return
      end,
    }
    package.loaded["commentry.config"] = {
      augroup = 1,
      diffview = { enabled = true },
      keymaps = { add_comment = "mc", edit_comment = "me", delete_comment = "md", set_comment_type = "mt" },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    Commands.cmd({ args = "next-unreviewed" })

    assert.are.same(1, called)
  end)

  it("includes file review commands in completion", function()
    vim.api.nvim_create_autocmd = function()
      return 1
    end
    package.loaded["commentry.comments"] = {
      list_comments = function()
        return
      end,
      set_comment_type = function()
        return
      end,
      toggle_file_reviewed = function()
        return
      end,
      next_unreviewed_file = function()
        return
      end,
      export_comments = function()
        return
      end,
      render_current_buffer = function()
        return
      end,
    }
    package.loaded["commentry.config"] = {
      augroup = 1,
      diffview = { enabled = true },
      keymaps = { add_comment = "mc", edit_comment = "me", delete_comment = "md", set_comment_type = "mt" },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    local toggle_matches = Commands.complete("Commentry toggle")
    local next_matches = Commands.complete("Commentry next")

    assert.is_true(vim.tbl_contains(toggle_matches, "toggle-file-reviewed"))
    assert.is_true(vim.tbl_contains(next_matches, "next-unreviewed"))
  end)

  it("routes list-comments with extra args without affecting handler selection", function()
    local called = 0
    vim.api.nvim_create_autocmd = function()
      return 1
    end

    package.loaded["commentry.comments"] = {
      list_comments = function()
        called = called + 1
      end,
      set_comment_type = function()
        return
      end,
      export_comments = function()
        return
      end,
      render_current_buffer = function()
        return
      end,
    }
    package.loaded["commentry.config"] = {
      augroup = 1,
      diffview = { enabled = true },
      keymaps = { add_comment = "mc", edit_comment = "me", delete_comment = "md", set_comment_type = "mt" },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    Commands.cmd({ args = "list-comments file.lua:1-3" })

    assert.are.same(1, called)
  end)

  it("passes resolved review context when opening commit range views", function()
    local open_args = nil
    local open_context = nil
    local resolve_args = nil

    vim.api.nvim_create_autocmd = function()
      return 1
    end
    package.loaded["commentry.comments"] = {
      list_comments = function()
        return
      end,
      set_comment_type = function()
        return
      end,
      export_comments = function(args)
        return
      end,
      render_current_buffer = function()
        return
      end,
    }
    package.loaded["commentry.config"] = {
      augroup = 1,
      diffview = { enabled = true },
      keymaps = { add_comment = "mc", edit_comment = "me", delete_comment = "md", set_comment_type = "mt" },
    }
    package.loaded["commentry.diffview"] = {
      resolve_review_context = function(args)
        resolve_args = vim.deepcopy(args)
        return {
          mode = "commit_range",
          root = "/tmp/project",
          revisions = { "HEAD~1..HEAD" },
          context_id = "/tmp/project::commit_range::HEAD~1..HEAD",
        }
      end,
      open = function(args, context)
        open_args = vim.deepcopy(args)
        open_context = vim.deepcopy(context)
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    Commands.cmd({ args = "open HEAD~1..HEAD" })

    assert.are.same({ "HEAD~1..HEAD" }, resolve_args)
    assert.are.same({ "HEAD~1..HEAD" }, open_args)
    assert.are.same("commit_range", open_context.mode)
    assert.are.same("/tmp/project::commit_range::HEAD~1..HEAD", open_context.context_id)
  end)

  it("routes :Commentry export to comments.export_comments with args", function()
    local called = 0
    local captured_args = nil
    vim.api.nvim_create_autocmd = function()
      return 1
    end

    package.loaded["commentry.comments"] = {
      list_comments = function()
        return
      end,
      set_comment_type = function()
        return
      end,
      export_comments = function(args)
        called = called + 1
        captured_args = args
      end,
      render_current_buffer = function()
        return
      end,
    }
    package.loaded["commentry.config"] = {
      augroup = 1,
      diffview = { enabled = true },
      keymaps = { add_comment = "mc", edit_comment = "me", delete_comment = "md", set_comment_type = "mt" },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    Commands.cmd({ args = "export register:a" })

    assert.are.same(1, called)
    assert.are.same("register:a", captured_args)
  end)

  it("routes :Commentry send-to-codex to orchestrator once with parsed opts", function()
    local orchestrator_calls = 0
    local seen_opts = nil
    local info_messages = {}
    local error_messages = {}

    vim.api.nvim_create_autocmd = function()
      return 1
    end
    package.loaded["commentry.util"] = {
      info = function(msg)
        info_messages[#info_messages + 1] = msg
      end,
      error = function(msg)
        error_messages[#error_messages + 1] = msg
      end,
      warn = function()
        return
      end,
      debug = function()
        return
      end,
    }
    package.loaded["commentry.codex.orchestrator"] = {
      send_current_review = function(opts)
        orchestrator_calls = orchestrator_calls + 1
        seen_opts = vim.deepcopy(opts)
        return {
          ok = true,
          code = "OK",
          adapter = "sidekick",
          dispatched_items = 3,
        }
      end,
    }
    package.loaded["commentry.comments"] = {
      list_comments = function()
        return
      end,
      set_comment_type = function()
        return
      end,
      export_comments = function()
        return
      end,
      render_current_buffer = function()
        return
      end,
    }
    package.loaded["commentry.config"] = {
      augroup = 1,
      codex = { enabled = true },
      diffview = { enabled = true },
      keymaps = { add_comment = "mc", edit_comment = "me", delete_comment = "md", set_comment_type = "mt" },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    Commands.cmd({
      args = "send-to-codex session_id=session-42 workspace=/tmp/repo adapter=sidekick fallback=none",
    })

    assert.are.same(1, orchestrator_calls)
    assert.are.same({
      session_id = "session-42",
      workspace = "/tmp/repo",
      adapter = "sidekick",
      fallback = "none",
    }, seen_opts)
    assert.are.same(0, #error_messages)
    assert.are.same("Sent 3 review item(s) to Codex via sidekick.", info_messages[1])
  end)

  it("shows actionable failure when send-to-codex has no target", function()
    local error_messages = {}

    vim.api.nvim_create_autocmd = function()
      return 1
    end
    package.loaded["commentry.util"] = {
      info = function()
        return
      end,
      error = function(msg)
        error_messages[#error_messages + 1] = msg
      end,
      warn = function()
        return
      end,
      debug = function()
        return
      end,
    }
    package.loaded["commentry.codex.orchestrator"] = {
      send_current_review = function()
        return {
          ok = false,
          code = "NO_TARGET",
          message = "No target adapter configured. Provide target.session_id or target.send.",
          retryable = false,
        }
      end,
    }
    package.loaded["commentry.comments"] = {
      list_comments = function()
        return
      end,
      set_comment_type = function()
        return
      end,
      export_comments = function()
        return
      end,
      render_current_buffer = function()
        return
      end,
    }
    package.loaded["commentry.config"] = {
      augroup = 1,
      codex = { enabled = true },
      diffview = { enabled = true },
      keymaps = { add_comment = "mc", edit_comment = "me", delete_comment = "md", set_comment_type = "mt" },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    Commands.cmd({ args = "send-to-codex" })

    assert.are.same(1, #error_messages)
    assert.are.same("table", type(error_messages[1]))
    local joined = table.concat(error_messages[1], "\n")
    assert.is_truthy(joined:find("Codex send failed %(NO_TARGET%)", 1, false))
    assert.is_truthy(joined:find("Provide a target session", 1, true))
  end)
end)
