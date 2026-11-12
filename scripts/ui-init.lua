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

local nui_root = cache_root .. "/nui.nvim"
if not vim.uv.fs_stat(nui_root) then
  vim.fn.system({ "git", "clone", "https://github.com/MunifTanjim/nui.nvim.git", nui_root })
  if vim.v.shell_error ~= 0 then
    error("Unable to install nui.nvim for UI capture")
  end
end
vim.fn.system({ "git", "-C", nui_root, "checkout", "10fc361835c856ba4233ef5ea135b919bf3dce97" })
if vim.v.shell_error ~= 0 then
  error("Unable to check out the pinned nui.nvim revision")
end
vim.opt.runtimepath:prepend(nui_root)
vim.opt.runtimepath:prepend(plugin_root)
vim.opt.runtimepath:prepend(diffview_root)

-- Optional local theme inputs for visual checks; CI uses Neovim defaults.
if vim.env.COMMENTRY_UI_THEME_RTP and vim.env.COMMENTRY_UI_THEME_RTP ~= "" then
  vim.opt.runtimepath:append(vim.env.COMMENTRY_UI_THEME_RTP)
end
if vim.env.COMMENTRY_UI_COLORSCHEME and vim.env.COMMENTRY_UI_COLORSCHEME ~= "" then
  vim.cmd.colorscheme(vim.env.COMMENTRY_UI_COLORSCHEME)
end

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
  },
})

local ok, diffview = pcall(require, "diffview")
if ok and type(diffview.setup) == "function" then
  diffview.setup({
    use_icons = false,
  })
end
