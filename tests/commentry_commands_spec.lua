---@module 'luassert'

describe("commentry keymap attachment", function()
  local original_comments
  local original_config
  local original_diffview
  local original_commands
  local original_create_autocmd
  local original_schedule
  local original_keymap_set

  before_each(function()
    original_comments = package.loaded["commentry.comments"]
    original_config = package.loaded["commentry.config"]
    original_diffview = package.loaded["commentry.diffview"]
    original_commands = package.loaded["commentry.commands"]
    original_create_autocmd = vim.api.nvim_create_autocmd
    original_schedule = vim.schedule
    original_keymap_set = vim.keymap.set
  end)

  after_each(function()
    package.loaded["commentry.comments"] = original_comments
    package.loaded["commentry.config"] = original_config
    package.loaded["commentry.diffview"] = original_diffview
    package.loaded["commentry.commands"] = original_commands
    vim.api.nvim_create_autocmd = original_create_autocmd
    vim.schedule = original_schedule
    vim.keymap.set = original_keymap_set
  end)

  it("attaches keymaps only for diffview buffers", function()
    local autocmd
    local mapped = {}
    local bufnr = vim.api.nvim_get_current_buf()
    vim.b[bufnr].commentry_diffview = false
    vim.b[bufnr].commentry_keymaps = nil

    vim.api.nvim_create_autocmd = function(_, opts)
      if opts.pattern == "DiffviewDiffBufWinEnter" then
        autocmd = opts
      end
      return 1
    end
    vim.schedule = function(cb)
      cb()
    end
    vim.keymap.set = function(mode, lhs, _, opts)
      mapped[#mapped + 1] = { mode = mode, lhs = lhs, opts = opts }
    end

    package.loaded["commentry.comments"] = {
      add_comment = function()
        return
      end,
      add_range_comment = function()
        return
      end,
      edit_comment = function()
        return
      end,
      delete_comment = function()
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
      list_comments = function()
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
      keymaps = {
        add_comment = "ga",
        add_range_comment = "gr",
        edit_comment = "ge",
        delete_comment = "gd",
        set_comment_type = "gt",
        toggle_file_reviewed = "gf",
        next_unreviewed_file = "gn",
        send_to_agent = "gs",
      },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    Commands.setup()
    autocmd.callback()

    assert.are.same(0, #mapped)
    assert.is_nil(vim.b[bufnr].commentry_keymaps)
  end)

  it("attaches configured keymaps once and reuses the line binding for visual ranges", function()
    local autocmd
    local mapped = {}
    local render_calls = 0
    local bufnr = vim.api.nvim_get_current_buf()
    vim.b[bufnr].commentry_diffview = true
    vim.b[bufnr].commentry_keymaps = nil

    vim.api.nvim_create_autocmd = function(_, opts)
      if opts.pattern == "DiffviewDiffBufWinEnter" then
        autocmd = opts
      end
      return 1
    end
    vim.schedule = function(cb)
      cb()
    end
    vim.keymap.set = function(mode, lhs, _, opts)
      mapped[#mapped + 1] = { mode = mode, lhs = lhs, desc = opts.desc, buffer = opts.buffer }
    end

    package.loaded["commentry.comments"] = {
      add_comment = function()
        return
      end,
      add_range_comment = function()
        return
      end,
      edit_comment = function()
        return
      end,
      delete_comment = function()
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
      list_comments = function()
        return
      end,
      export_comments = function()
        return
      end,
      render_current_buffer = function()
        render_calls = render_calls + 1
      end,
    }
    package.loaded["commentry.config"] = {
      augroup = 1,
      diffview = { enabled = true },
      keymaps = {
        add_comment = "ga",
        edit_comment = "ge",
        delete_comment = "gd",
        set_comment_type = "gt",
        toggle_file_reviewed = "gf",
        next_unreviewed_file = "gn",
      },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    Commands.setup()
    autocmd.callback()
    local first_count = #mapped
    autocmd.callback()

    assert.are.same(first_count, #mapped)
    assert.is_true(render_calls > 0)
    assert.is_true(vim.b[bufnr].commentry_keymaps)

    local bindings = {}
    for _, mapping in ipairs(mapped) do
      bindings[mapping.mode .. ":" .. mapping.lhs] = mapping.buffer
    end
    assert.are.same(bufnr, bindings["n:ga"])
    assert.are.same(bufnr, bindings["x:ga"])
    assert.are.same(bufnr, bindings["n:ge"])
    assert.are.same(bufnr, bindings["n:gd"])
    assert.are.same(bufnr, bindings["n:gt"])
    assert.are.same(bufnr, bindings["n:gf"])
    assert.are.same(bufnr, bindings["n:gn"])
  end)

  it("attaches keymaps when diffview marker is missing but current context matches buffer", function()
    local autocmd
    local mapped = {}
    local bufnr = vim.api.nvim_get_current_buf()
    vim.b[bufnr].commentry_diffview = nil
    vim.b[bufnr].commentry_keymaps = nil

    vim.api.nvim_create_autocmd = function(_, opts)
      if opts.pattern == "DiffviewDiffBufWinEnter" then
        autocmd = opts
      end
      return 1
    end
    vim.keymap.set = function(mode, lhs, _, opts)
      mapped[#mapped + 1] = { mode = mode, lhs = lhs, desc = opts.desc, buffer = opts.buffer }
    end

    package.loaded["commentry.comments"] = {
      add_comment = function()
        return
      end,
      add_range_comment = function()
        return
      end,
      edit_comment = function()
        return
      end,
      delete_comment = function()
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
      list_comments = function()
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
      keymaps = nil,
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
      current_file_context = function()
        return { bufnr = bufnr }
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    Commands.setup()
    autocmd.callback()

    assert.are.same(9, #mapped)
    assert.is_true(vim.b[bufnr].commentry_keymaps)
    assert.is_true(vim.b[bufnr].commentry_diffview)
  end)

  it("treats empty disable as scoped to file review toggles", function()
    local autocmd
    local mapped = {}
    local bufnr = vim.api.nvim_get_current_buf()
    vim.b[bufnr].commentry_diffview = true
    vim.b[bufnr].commentry_keymaps = nil

    vim.api.nvim_create_autocmd = function(_, opts)
      if opts.pattern == "DiffviewDiffBufWinEnter" then
        autocmd = opts
      end
      return 1
    end
    vim.schedule = function(cb)
      cb()
    end
    vim.keymap.set = function(mode, lhs, _, opts)
      mapped[#mapped + 1] = { mode = mode, lhs = lhs, desc = opts.desc }
    end

    package.loaded["commentry.comments"] = {
      add_comment = function()
        return
      end,
      add_range_comment = function()
        return
      end,
      edit_comment = function()
        return
      end,
      delete_comment = function()
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
      list_comments = function()
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
      keymaps = {
        add_comment = "",
        add_range_comment = "",
        edit_comment = "",
        delete_comment = "",
        set_comment_type = "",
        toggle_file_reviewed = "",
        next_unreviewed_file = "",
        send_to_agent = "",
        list_comments = "",
      },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    Commands.setup()
    autocmd.callback()

    local lhs_by_desc = {}
    for _, mapping in ipairs(mapped) do
      lhs_by_desc[mapping.desc] = mapping.lhs
    end
    assert.is_string(lhs_by_desc["Commentry add comment"])
    assert.is_string(lhs_by_desc["Commentry add range comment"])
    assert.is_string(lhs_by_desc["Commentry edit comment"])
    assert.is_string(lhs_by_desc["Commentry delete comment"])
    assert.is_string(lhs_by_desc["Commentry set comment type"])
    assert.is_string(lhs_by_desc["Commentry send to agent"])
    assert.is_string(lhs_by_desc["Commentry list comments"])
    assert.is_nil(lhs_by_desc["Commentry toggle file reviewed"])
    assert.is_nil(lhs_by_desc["Commentry jump next unreviewed file"])
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
  local original_agent_preload
  local original_diagnostics

  before_each(function()
    original_comments = package.loaded["commentry.comments"]
    original_config = package.loaded["commentry.config"]
    original_diffview = package.loaded["commentry.diffview"]
    original_commands = package.loaded["commentry.commands"]
    original_create_autocmd = vim.api.nvim_create_autocmd
    original_util = package.loaded["commentry.util"]
    original_orchestrator = package.loaded["commentry.agent.orchestrator"]
    original_agent_preload = package.preload["commentry.agent"]
    original_diagnostics = package.loaded["commentry.diagnostics"]
  end)

  after_each(function()
    package.loaded["commentry.comments"] = original_comments
    package.loaded["commentry.config"] = original_config
    package.loaded["commentry.diffview"] = original_diffview
    package.loaded["commentry.commands"] = original_commands
    package.loaded["commentry.util"] = original_util
    package.loaded["commentry.agent.orchestrator"] = original_orchestrator
    package.loaded["commentry.diagnostics"] = original_diagnostics
    vim.api.nvim_create_autocmd = original_create_autocmd
    package.preload["commentry.agent"] = original_agent_preload
  end)

  it("filters public command completion by the typed prefix", function()
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
    assert.are.same({ "list-comments" }, Commands.complete("Commentry list"))
    assert.are.same({ "export" }, Commands.complete("Commentry ex"))
    assert.are.same({ "inbox" }, Commands.complete("Commentry in"))
    assert.are.same({}, Commands.complete("Commentry nonexistent"))
  end)

  it("passes list-comments filters to the picker", function()
    local called = 0
    local captured_args = nil
    vim.api.nvim_create_autocmd = function()
      return 1
    end

    package.loaded["commentry.comments"] = {
      list_comments = function(args)
        called = called + 1
        captured_args = args
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
    Commands.cmd({ args = "list-comments unresolved" })

    assert.are.same(1, called)
    assert.are.same("unresolved", captured_args)
  end)

  it("routes reattachment args and completes recovery commands and filters", function()
    local captured = nil
    vim.api.nvim_create_autocmd = function()
      return 1
    end

    package.loaded["commentry.comments"] = {
      list_comments = function() end,
      reattach_comment = function(args)
        captured = args
      end,
      set_comment_type = function() end,
      export_comments = function() end,
      render_current_buffer = function() end,
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
    local args = { args = "reattach", range = 2, line1 = 4, line2 = 6 }
    Commands.cmd(args)

    assert.are.same(args, captured)
    assert.are.same({ "unresolved" }, Commands.complete("Commentry list-comments un"))
    assert.is_true(vim.tbl_contains(Commands.complete("Commentry re"), "reattach"))
    assert.is_true(vim.tbl_contains(Commands.complete("Commentry he"), "help"))
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

  it("routes :Commentry send-to-agent to orchestrator once with implicit target resolution", function()
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
    package.loaded["commentry.agent.orchestrator"] = {
      send_current_review = function(opts)
        orchestrator_calls = orchestrator_calls + 1
        seen_opts = vim.deepcopy(opts)
        return {
          ok = true,
          code = "OK",
          adapter = "sidekick",
          delegated = true,
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
      agent = { enabled = true },
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
    Commands.cmd({ args = "send-to-agent" })

    assert.are.same(1, orchestrator_calls)
    assert.are.same({}, seen_opts)
    assert.are.same(0, #error_messages)
    assert.are.same("Delegated 3 review item(s) to Sidekick.", info_messages[1])
  end)

  it("prefers async orchestrator send when available", function()
    local async_calls = 0
    local sync_calls = 0
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
    package.loaded["commentry.agent.orchestrator"] = {
      send_current_review = function()
        sync_calls = sync_calls + 1
        return {
          ok = true,
          code = "OK",
          adapter = "sync",
          dispatched_items = 1,
        }
      end,
      send_current_review_async = function(opts, cb)
        async_calls = async_calls + 1
        cb({
          ok = true,
          code = "OK",
          adapter = "sidekick",
          delegated = true,
          dispatched_items = 2,
        })
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
      agent = { enabled = true },
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
    Commands.cmd({ args = "send-to-agent" })

    assert.are.same(1, async_calls)
    assert.are.same(0, sync_calls)
    assert.are.same(0, #error_messages)
    assert.are.same("Delegated 2 review item(s) to Sidekick.", info_messages[1])
  end)

  it("shows actionable failure when send-to-agent has no target", function()
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
    package.loaded["commentry.agent.orchestrator"] = {
      send_current_review = function()
        return {
          ok = false,
          code = "NO_TARGET",
          message = "No agent target is available.",
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
      agent = { enabled = true },
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
    Commands.cmd({ args = "send-to-agent" })

    assert.are.same(1, #error_messages)
    assert.are.same("table", type(error_messages[1]))
    local joined = table.concat(error_messages[1], "\n")
    assert.is_truthy(joined:find("Agent send failed %(NO_TARGET%)", 1, false))
    assert.is_truthy(joined:find("Use Sidekick to select an agent", 1, true))
  end)

  it("shows retry-ready failure when send-to-agent transport fails", function()
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
    package.loaded["commentry.agent.orchestrator"] = {
      send_current_review = function()
        return {
          ok = false,
          code = "TRANSPORT_FAILED",
          message = "Agent transport failed. Retry.",
          retryable = true,
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
      agent = { enabled = true },
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
    Commands.cmd({ args = "send-to-agent" })

    assert.are.same(1, #error_messages)
    assert.are.same("table", type(error_messages[1]))
    local joined = table.concat(error_messages[1], "\n")
    assert.is_truthy(joined:find("Agent send failed %(TRANSPORT_FAILED%)", 1, false))
    assert.is_truthy(joined:find("Agent transport failed%. Retry%.", 1, false))
    assert.is_truthy(joined:find("retryable", 1, true))
  end)
end)
