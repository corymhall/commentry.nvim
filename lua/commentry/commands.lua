local Config = require("commentry.config")
local Util = require("commentry.util")
local M = { commands = {} }
local initialized = false

function M.attach(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].commentry_keymaps then
    return
  end
  local context = require("commentry.diffview").current_file_context(buf)
  if not context then
    return
  end
  vim.b[buf].commentry_keymaps = true
  local mappings = {
    {
      "n",
      "add_comment",
      function()
        require("commentry.inbox").comment()
      end,
      "Create inbox comment",
    },
    {
      "x",
      "add_range_comment",
      function()
        -- Leave Visual mode before opening the composer, preserving its exact range.
        local first, last = vim.fn.line("v"), vim.fn.line(".")
        vim.cmd.normal({ args = { "\27" }, bang = true })
        require("commentry.inbox").comment({ range = 2, line1 = math.min(first, last), line2 = math.max(first, last) })
      end,
      "Create inbox range comment",
    },
    {
      "n",
      "list_comments",
      function()
        require("commentry.inbox").open(nil, { project = context.project })
      end,
      "Open project inbox",
    },
  }
  for _, mapping in ipairs(mappings) do
    local key = Config.keymaps[mapping[2]]
    if key and key ~= "" then
      vim.keymap.set(mapping[1], key, mapping[3], { buffer = buf, desc = "Commentry " .. mapping[4] })
    end
  end
  vim.api.nvim_buf_call(buf, function()
    if vim.fn.maparg("gC", "n") == "" then
      vim.keymap.set("n", "gC", function()
        require("commentry.inbox.locations").open_at_cursor()
      end, { buffer = buf, desc = "Open inbox thread at cursor" })
    end
  end)
end

function M.register(name, fn)
  M.commands[name] = fn
end

function M.setup()
  if initialized then
    return
  end
  initialized = true
  M.register("inbox", function(_, scope)
    if not vim.tbl_contains({ "", "all", "unread", "read", "open", "resolved", "queued" }, scope) then
      Util.error("Use :Commentry inbox [all|unread|read|open|resolved|queued]")
      return
    end
    require("commentry.inbox").open(scope)
  end)
  M.register("comment", function(args)
    require("commentry.inbox").comment(args)
  end)
  M.register("edit", function()
    require("commentry.inbox").edit()
  end)
  M.register("capture-text", function(_, register)
    require("commentry.inbox").capture_text(register)
  end)
  M.register("new-thread", function()
    require("commentry.inbox").new_thread()
  end)
  M.register("open", function(_, args)
    if not Config.diffview.enabled then
      Util.warn("Diff view is disabled in config")
      return
    end
    local ok, err = require("commentry.diffview").open(vim.split(args, "%s+", { trimempty = true }))
    if not ok then
      Util.error(err)
    end
  end)
  M.register("help", function()
    vim.cmd.help("commentry")
  end)
  M.register("diagnostics", function()
    require("commentry.diagnostics").open()
  end)
end

function M.complete(line)
  M.setup()
  local prefix = line:gsub("^%s*Commentry%s+", ""):match("^(%S*)") or ""
  local keys = vim.tbl_keys(M.commands)
  table.sort(keys)
  return vim.tbl_filter(function(key)
    return key:find(prefix, 1, true) == 1
  end, keys)
end

function M.cmd(line)
  M.setup()
  local parts = vim.split(line.args or "", "%s+", { trimempty = true })
  local command = M.commands[parts[1] or ""]
  if not command then
    Util.error("Unknown Commentry command. Use :Commentry help")
    return
  end
  command(line, table.concat(parts, " ", 2))
end

return M
