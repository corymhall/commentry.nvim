if vim.g.loaded_commentry then
  return
end
vim.g.loaded_commentry = true

vim.api.nvim_create_user_command("Commentry", function(args)
  require("commentry.commands").cmd(args)
end, {
  range = true,
  nargs = "?",
  desc = "Commentry",
  complete = function(_, line)
    return require("commentry.commands").complete(line)
  end,
})
