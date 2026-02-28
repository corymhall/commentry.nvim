---@module 'luassert'

describe("commentry plugin entrypoint", function()
  local original_create_user_command
  local original_loaded_commentry
  local original_commentry
  local original_commands

  before_each(function()
    original_create_user_command = vim.api.nvim_create_user_command
    original_loaded_commentry = vim.g.loaded_commentry
    original_commentry = package.loaded["commentry"]
    original_commands = package.loaded["commentry.commands"]
    vim.g.loaded_commentry = nil
  end)

  after_each(function()
    vim.api.nvim_create_user_command = original_create_user_command
    vim.g.loaded_commentry = original_loaded_commentry
    package.loaded["commentry"] = original_commentry
    package.loaded["commentry.commands"] = original_commands
  end)

  it("routes :Commentry without re-running setup()", function()
    local command_cb = nil
    local called_cmd = false

    vim.api.nvim_create_user_command = function(name, cb)
      if name == "Commentry" then
        command_cb = cb
      end
    end

    package.loaded["commentry"] = {
      setup = function()
        error("plugin entrypoint must not call commentry.setup()")
      end,
    }
    package.loaded["commentry.commands"] = {
      cmd = function()
        called_cmd = true
      end,
      complete = function()
        return {}
      end,
    }

    dofile(vim.fs.normalize(vim.uv.cwd() .. "/plugin/commentry.lua"))

    assert.is_not_nil(command_cb)
    assert.has_no.errors(function()
      command_cb({ args = "" })
    end)
    assert.is_true(called_cmd)
  end)
end)
