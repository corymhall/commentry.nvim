describe("Commentry command entrypoint", function()
  it("opens the shared inbox and passes source ranges unchanged", function()
    local original = package.loaded["commentry.inbox"]
    local scope, range
    package.loaded["commentry.inbox"] = {
      open = function(value)
        scope = value
      end,
      comment = function(args)
        range = args
      end,
    }
    local ok, err = pcall(function()
      local commands = require("commentry.commands")
      commands.cmd({ args = "inbox unread" })
      assert.are.same("unread", scope)
      local args = { args = "comment", range = 2, line1 = 3, line2 = 7 }
      commands.cmd(args)
      assert.are.same(args, range)
    end)
    package.loaded["commentry.inbox"] = original
    assert.is_true(ok, tostring(err))
  end)
end)
