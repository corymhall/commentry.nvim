describe("Rex inbox launcher", function()
  it("makes nested Rex and Neovim commands discoverable with a GUI-only PATH", function()
    local original_rex, original_getenv = _G.rex, os.getenv
    local home = "/Users/test user"
    local rex_bin = home
      .. "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS"
    local actions, selected, launched = {}, nil, nil
    local available = { [rex_bin .. "/rex"] = true, ["/opt/homebrew/bin/nvim"] = true }
    local function discover(name, path)
      for directory in path:gmatch("[^:]+") do
        if available[directory .. "/" .. name] then
          return true
        end
      end
      return false
    end
    os.getenv = function(name)
      return ({ HOME = home, PATH = "/usr/bin:/bin" })[name]
    end
    _G.rex = {
      action = function(action)
        actions[action.name] = action.run
      end,
      exec = function(args, opts)
        if args[1] == "sleep" then
          return { ok = true }
        end
        launched = args
        -- Simulate the subprocesses the real Commentry CLI must resolve.
        if not discover("rex", opts.env.PATH) or not discover("nvim", opts.env.PATH) then
          return { ok = false, stderr = "nested executable not found", stdout = "" }
        end
        return { ok = true, stdout = '{"ok":true,"result":{"window":"inbox-window"}}' }
      end,
      json = { decode = vim.json.decode },
      client = {
        queue = function(_, args)
          selected = args
        end,
      },
    }
    local ok, err = pcall(function()
      dofile("integrations/rex/commentry.lua")
      actions.commentry_inbox({ session_id = "session", block_id = "block", client_id = "client" })
      assert.are.same("commentry", launched[1])
      assert.are.same("inbox", launched[#launched])
      assert.are.same({ session_id = "session", window_id = "inbox-window" }, selected)
    end)
    _G.rex, os.getenv = original_rex, original_getenv
    assert.is_true(ok, tostring(err))
  end)
end)
