-- Minimal reproduction config for commentry.nvim bug reports.
-- Usage: nvim --clean -u repro.lua

local root = vim.fn.stdpath("run") .. "/commentry-repro"
vim.fn.mkdir(root, "p")

for _, name in ipairs({ "config", "data", "state", "cache" }) do
  vim.env[("XDG_%s_HOME"):format(name:upper())] = root .. "/" .. name
end

local lazypath = root .. "/plugins/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
end
vim.opt.runtimepath:prepend(lazypath)

require("lazy").setup({
  {
    "sindrets/diffview.nvim",
    lazy = false,
  },
  {
    dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h"),
    opts = {},
  },
}, { root = root .. "/plugins" })
