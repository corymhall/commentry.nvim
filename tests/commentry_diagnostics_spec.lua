---@module 'luassert'

describe("commentry.diagnostics", function()
  local original_diagnostics
  local original_config
  local original_comments
  local original_store
  local original_diffview
  local original_log
  local original_cmd
  local original_set_lines

  before_each(function()
    original_diagnostics = package.loaded["commentry.diagnostics"]
    original_config = package.loaded["commentry.config"]
    original_comments = package.loaded["commentry.comments"]
    original_store = package.loaded["commentry.store"]
    original_diffview = package.loaded["commentry.diffview"]
    original_log = package.loaded["commentry.log"]
    original_cmd = vim.cmd
    original_set_lines = vim.api.nvim_buf_set_lines
    package.loaded["commentry.diagnostics"] = nil
  end)

  after_each(function()
    package.loaded["commentry.diagnostics"] = original_diagnostics
    package.loaded["commentry.config"] = original_config
    package.loaded["commentry.comments"] = original_comments
    package.loaded["commentry.store"] = original_store
    package.loaded["commentry.diffview"] = original_diffview
    package.loaded["commentry.log"] = original_log
    vim.cmd = original_cmd
    vim.api.nvim_buf_set_lines = original_set_lines
  end)

  it("dumps config/store/diffview state", function()
    package.loaded["commentry.config"] = {
      log = { level = "info", sink = "echo" },
      codex = { enabled = true },
    }
    package.loaded["commentry.comments"] = {
      debug_store_context = function()
        return {
          store_path = "/tmp/commentry.json",
          context_id = "ctx-1",
          store_exists = true,
        }
      end,
    }
    package.loaded["commentry.store"] = {
      debug_state = function()
        return { home = "/tmp/home" }
      end,
    }
    package.loaded["commentry.diffview"] = {
      debug_state = function()
        return { attached = true, bufnr = 12 }
      end,
    }
    package.loaded["commentry.log"] = {
      info = function() end,
    }

    local Diagnostics = require("commentry.diagnostics")
    local text = Diagnostics.dump()

    assert.is_truthy(text:find("commentry.nvim diagnostics", 1, true))
    assert.is_truthy(text:find("log.level=info", 1, true))
    assert.is_truthy(text:find("store=/tmp/commentry.json", 1, true))
    assert.is_truthy(text:find("context=ctx-1", 1, true))
    assert.is_truthy(text:find("diffview.attached=true", 1, true))
  end)

  it("opens diagnostics in a scratch buffer", function()
    local opened = false
    local written_lines = nil
    vim.cmd = function(cmd)
      if cmd == "new" then
        opened = true
      end
    end
    vim.api.nvim_buf_set_lines = function(_, _, _, _, lines)
      written_lines = lines
    end

    package.loaded["commentry.config"] = {}
    package.loaded["commentry.log"] = { info = function() end }

    local Diagnostics = require("commentry.diagnostics")
    Diagnostics.open()

    assert.is_true(opened)
    assert.is_true(type(written_lines) == "table" and #written_lines > 0)
  end)
end)
