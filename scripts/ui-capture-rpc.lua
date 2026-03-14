local function read_env(name, default)
  local value = vim.env[name]
  if type(value) ~= "string" or value == "" then
    return default
  end
  return value
end

local function read_env_number(name, default)
  local value = tonumber(read_env(name, ""))
  if type(value) ~= "number" or value <= 0 then
    return default
  end
  return math.floor(value)
end

local root = assert(vim.env.COMMENTRY_REPO_ROOT, "COMMENTRY_REPO_ROOT is required")
vim.opt.runtimepath:prepend(root)

local Bridge = require("commentry.dev.ui_bridge")
local cache = assert(vim.env.COMMENTRY_UI_CACHE, "COMMENTRY_UI_CACHE is required")
local cwd = assert(vim.env.COMMENTRY_UI_CWD, "COMMENTRY_UI_CWD is required")
local out_dir = read_env("COMMENTRY_UI_OUT_DIR", cwd)
local scenario = read_env("COMMENTRY_UI_SCENARIO", "popup")
local columns = read_env_number("COMMENTRY_UI_COLUMNS", 220)
local lines = read_env_number("COMMENTRY_UI_LINES", 18)

local bridge = Bridge.Bridge.new({
  cmd = "nvim",
  args = {
    "--embed",
    "--clean",
    "-u",
    root .. "/scripts/ui-init.lua",
  },
  cwd = cwd,
  env = {
    COMMENTRY_REPO_ROOT = root,
    COMMENTRY_UI_CACHE = cache,
  },
  width = columns,
  height = lines,
})

local ok, err = xpcall(function()
  bridge:request("nvim_ui_attach", {
    columns,
    lines,
    {
      rgb = true,
      ext_linegrid = true,
      ext_multigrid = true,
    },
  }, 5000)

  bridge:wait_for_flush(5000)
  bridge:request("nvim_command", { "Commentry open" }, 5000)

  bridge:wait_until(5000, function()
    local result = bridge:request("nvim_exec_lua", {
      [[
        local diffview = require("commentry.diffview")
        local view = diffview.get_current_view()
        return type(view) == "table" and view.ready == true
      ]],
      {},
    }, 5000)
    return result == true
  end)
  bridge:wait_for_flush(5000)

  bridge:wait_until(5000, function()
    local ok = bridge:request("nvim_exec_lua", {
      [[
        local diffview = require("commentry.diffview")
        local view = diffview.get_current_view()
        if type(view) ~= "table" then
          return false
        end
        local focused = diffview.focus_file_side(view, "head")
        if not focused then
          return false
        end
        local context = diffview.current_file_context()
        if not context then
          return false
        end
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        return true
      ]],
      {},
    }, 5000)
    return ok == true
  end)
  bridge:wait_for_flush(5000)

  if scenario == "popup" then
    bridge:request("nvim_input", { "mc" }, 2000)
    bridge:wait_until(5000, function()
      for _, window in pairs(bridge.screen.windows) do
        if window.kind == "float" and not window.hidden then
          return true
        end
      end
      return false
    end)
    local snapshot = bridge.screen:snapshot("rpc-comment-popup")
    Bridge.write_snapshot_files(snapshot, bridge.screen, out_dir, "rpc-comment-popup")
    return
  end

  if scenario == "card" then
    bridge:request("nvim_exec_lua", {
      [[
        local comments = require("commentry.comments")
        comments._set_input_provider_for_tests(function(_, cb)
          cb("Consider renaming this variable to reflect the reviewed value.", "suggestion")
        end)
        comments.add_comment()
        comments._set_input_provider_for_tests(nil)
        return true
      ]],
      {},
    }, 5000)
    bridge:wait_for_flush(5000)
    local snapshot = bridge.screen:snapshot("rpc-comment-card")
    Bridge.write_snapshot_files(snapshot, bridge.screen, out_dir, "rpc-comment-card")
    return
  end

  if scenario == "range" then
    bridge:request("nvim_exec_lua", {
      [[
        local comments = require("commentry.comments")
        comments._set_input_provider_for_tests(function(_, cb)
          cb("This change spans a few lines, so the range affordance should feel connected to the edited block.", "issue")
        end)
        local bufnr = vim.api.nvim_get_current_buf()
        vim.fn.setpos("'<", { bufnr, 2, 1, 0 })
        vim.fn.setpos("'>", { bufnr, 4, 1, 0 })
        comments.add_range_comment()
        comments._set_input_provider_for_tests(nil)
        return true
      ]],
      {},
    }, 5000)
    bridge:wait_for_flush(5000)
    local snapshot = bridge.screen:snapshot("rpc-range-comment")
    Bridge.write_snapshot_files(snapshot, bridge.screen, out_dir, "rpc-range-comment")
    return
  end

  error(("Unknown scenario: %s"):format(scenario))
end, debug.traceback)

bridge:close()

if not ok then
  error(err)
end
