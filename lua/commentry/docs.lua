local M = {}

local public_command_refs = {
  ":Commentry open",
  ":Commentry add-range-comment",
  ":Commentry list-comments",
  ":Commentry set-comment-type",
  ":Commentry toggle-file-reviewed",
  ":Commentry next-unreviewed",
  ":Commentry export",
  ":Commentry debug-store",
  ":Commentry diagnostics",
  ":Commentry send-to-codex",
}

local required_help_tags = {
  "commentry",
  "commentry.install",
  "commentry.setup",
  "commentry.dependencies",
  "commentry.keymaps",
  "commentry.commands",
  "commentry.v1-boundaries",
  "commentry.persistence",
  "commentry.troubleshooting",
}

---@param path string
---@return string
local function read_file(path)
  local fd, err = io.open(path, "r")
  if not fd then
    error(("Unable to read %s: %s"):format(path, err or "unknown error"))
  end

  local content = fd:read("*a")
  fd:close()
  return content
end

---@param errors string[]
---@param label string
---@param needle string
---@param haystack string
local function expect_contains(errors, label, needle, haystack)
  if not haystack:find(needle, 1, true) then
    errors[#errors + 1] = ("%s is missing %q"):format(label, needle)
  end
end

---@return string[]
local function keymap_actions()
  local Config = require("commentry.config")
  local actions = vim.tbl_keys(Config.default_keymaps or {})
  table.sort(actions)
  return actions
end

---@param path string
---@return string
local function validate_help_tags(path)
  local tempdir = vim.fn.tempname()
  vim.fn.mkdir(tempdir, "p")

  local helpfile = vim.fs.joinpath(tempdir, "commentry.txt")
  vim.fn.writefile(vim.split(read_file(path), "\n", { plain = true }), helpfile)
  vim.cmd("silent helptags " .. vim.fn.fnameescape(tempdir))

  local tags_path = vim.fs.joinpath(tempdir, "tags")
  local tags = read_file(tags_path)
  pcall(vim.fn.delete, tempdir, "rf")
  return tags
end

---@param errors string[]
---@param label string
---@param content string
local function validate_public_surface(errors, label, content)
  for _, command_ref in ipairs(public_command_refs) do
    expect_contains(errors, label, command_ref, content)
  end

  for _, action in ipairs(keymap_actions()) do
    expect_contains(errors, label, action, content)
  end

  for _, token in ipairs({ "diffview.nvim", "snacks.nvim", "Sidekick", "auto_attach", "comment_ranges" }) do
    expect_contains(errors, label, token, content)
  end
end

function M.check()
  local root = vim.fn.getcwd()
  local readme_path = vim.fs.joinpath(root, "README.md")
  local help_path = vim.fs.joinpath(root, "doc", "commentry.txt")

  local readme = read_file(readme_path)
  local help = read_file(help_path)
  local tags = validate_help_tags(help_path)
  local errors = {}

  validate_public_surface(errors, "README.md", readme)
  validate_public_surface(errors, "doc/commentry.txt", help)

  expect_contains(errors, "README.md", "Validate docs: `./scripts/docs`", readme)
  expect_contains(errors, "README.md", "Required:", readme)
  expect_contains(errors, "README.md", "Optional integrations:", readme)

  expect_contains(errors, "doc/commentry.txt", "*commentry.txt*", help)
  expect_contains(errors, "doc/commentry.txt", "Required dependencies:", help)
  expect_contains(errors, "doc/commentry.txt", "Optional integrations:", help)

  for _, tag in ipairs(required_help_tags) do
    expect_contains(errors, "doc/tags", tag .. "\tcommentry.txt", tags)
  end

  if #errors > 0 then
    error("commentry docs validation failed:\n- " .. table.concat(errors, "\n- "))
  end

  print("commentry docs validation: OK")
end

function M.update()
  return M.check()
end

return M
