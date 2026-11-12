local M = {}
local installed = {}

local actions = {
  { "n", "add_comment", "comment", "Comment on current line" },
  { "x", "add_range_comment", "comment", "Comment on selected lines" },
  { "n", "edit_comment", "edit", "Edit pending comment at cursor" },
  { "n", "new_thread", "new-thread", "New project thread" },
  { "n", "inbox", "inbox", "Project inbox" },
  { "n", "unread", "inbox unread", "Unread project inbox" },
  { "n", "all_projects", "inbox all", "Inbox across all projects" },
  { "n", "clipboard", "capture-text +", "Comment on clipboard text" },
  { "n", "open_diff", "open", "Open Diffview" },
}

function M.setup(config)
  -- Delete only mappings we still own, even if the user changed mapleader.
  for _, owned in ipairs(installed) do
    for _, mapping in ipairs(vim.api.nvim_get_keymap(owned.mode)) do
      if mapping.callback == owned.callback then
        vim.keymap.del(owned.mode, mapping.lhs)
      end
    end
  end
  installed = {}
  for _, action in ipairs(actions) do
    local mode, name, command, description = unpack(action)
    local lhs = config[name]
    if lhs and lhs ~= "" then
      if vim.fn.maparg(lhs, mode) ~= "" then
        require("commentry.util").warn("Commentry mapping already exists, skipping " .. lhs .. " in mode " .. mode)
      else
        local callback = function()
          local args = { args = command, range = 0 }
          if mode == "x" then
            local first, last = vim.fn.line("v"), vim.fn.line(".")
            vim.cmd.normal({ args = { "\27" }, bang = true })
            args.range, args.line1, args.line2 = 2, math.min(first, last), math.max(first, last)
          end
          require("commentry.commands").cmd(args)
        end
        vim.keymap.set(mode, lhs, callback, { desc = "Commentry " .. description, silent = true })
        installed[#installed + 1] = { mode = mode, callback = callback }
      end
    end
  end
end

return M
