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
    local received_args

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
      cmd = function(args)
        received_args = args
      end,
      complete = function()
        return {}
      end,
    }

    dofile(vim.fs.normalize(vim.uv.cwd() .. "/plugin/commentry.lua"))

    assert.is_not_nil(command_cb)
    command_cb({ args = "inbox unread", range = 0 })
    assert.are.same("inbox unread", received_args.args)
    assert.are.same(0, received_args.range)
  end)
end)
