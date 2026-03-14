local plugin_root = vim.env.COMMENTRY_REPO_ROOT
local cache_root = vim.env.COMMENTRY_UI_CACHE

if type(plugin_root) ~= "string" or plugin_root == "" then
  error("COMMENTRY_REPO_ROOT is required")
end

if type(cache_root) ~= "string" or cache_root == "" then
  error("COMMENTRY_UI_CACHE is required")
end

local diffview_root = cache_root .. "/diffview.nvim"

vim.fn.mkdir(cache_root, "p")
if not vim.uv.fs_stat(diffview_root) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/sindrets/diffview.nvim.git",
    diffview_root,
  })
end

vim.opt.runtimepath:prepend(plugin_root)
vim.opt.runtimepath:prepend(diffview_root)

local helptags = diffview_root .. "/doc/tags"
if not vim.uv.fs_stat(helptags) then
  pcall(vim.cmd.helptags, diffview_root .. "/doc")
end

vim.opt.termguicolors = true
vim.opt.laststatus = 0
vim.opt.showmode = false

require("commentry").setup({
  log = {
    level = "warn",
    sink = "echo",
  },
  diffview = {
    auto_attach = true,
    comment_cards = {
      max_width = 58,
      max_body_lines = 6,
      show_markers = true,
    },
  },
})

local ok, diffview = pcall(require, "diffview")
if ok and type(diffview.setup) == "function" then
  diffview.setup({
    use_icons = false,
  })
end
