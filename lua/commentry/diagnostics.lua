local M = {}

local Log = require("commentry.log")

---@param mod string
---@return any|nil
local function safe_require(mod)
  local ok, loaded = pcall(require, mod)
  if ok then
    return loaded
  end
  return nil
end

---@return string
function M.dump()
  local Config = safe_require("commentry.config")
  local Comments = safe_require("commentry.comments")
  local Diffview = safe_require("commentry.diffview")

  local lines = {}
  local version = vim.version()
  lines[#lines + 1] = "commentry.nvim diagnostics"
  lines[#lines + 1] = ("nvim: %d.%d.%d"):format(version.major, version.minor, version.patch)

  if type(Config) == "table" then
    local log_config = type(Config.log) == "table" and Config.log or {}
    local codex_config = type(Config.codex) == "table" and Config.codex or {}
    lines[#lines + 1] = ("log.level=%s"):format(tostring(log_config.level))
    lines[#lines + 1] = ("log.sink=%s"):format(tostring(log_config.sink))
    lines[#lines + 1] = ("codex.enabled=%s"):format(tostring(codex_config.enabled))
  end

  if type(Comments) == "table" and type(Comments.debug_store_context) == "function" then
    local info = Comments.debug_store_context()
    if type(info) == "table" then
      lines[#lines + 1] = ("store=%s"):format(info.store_path or "nil")
      lines[#lines + 1] = ("context=%s"):format(info.context_id or "nil")
      lines[#lines + 1] = ("store.exists=%s"):format(tostring(info.store_exists))
    end
  end

  if type(Diffview) == "table" and type(Diffview.debug_state) == "function" then
    local state = Diffview.debug_state()
    if type(state) == "table" then
      lines[#lines + 1] = ("diffview.attached=%s"):format(tostring(state.attached))
      lines[#lines + 1] = ("diffview.buf=%s"):format(tostring(state.bufnr))
      if type(state.error) == "string" and state.error ~= "" then
        lines[#lines + 1] = ("diffview.error=%s"):format(state.error)
      end
    end
  end

  Log.info("diagnostics.dump", { lines = #lines })
  return table.concat(lines, "\n")
end

function M.open()
  local text = M.dump()
  local Config = safe_require("commentry.config")
  local style = "split"
  if
    type(Config) == "table"
    and type(Config.diagnostics) == "table"
    and type(Config.diagnostics.open_style) == "string"
  then
    style = Config.diagnostics.open_style
  end

  local bufnr = nil
  if style == "float" then
    bufnr = vim.api.nvim_create_buf(false, true)
    local width = math.max(60, math.floor(vim.o.columns * 0.7))
    local height = math.max(10, math.floor(vim.o.lines * 0.6))
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    vim.api.nvim_open_win(bufnr, true, {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      style = "minimal",
      border = "rounded",
      title = " Commentry Diagnostics ",
      title_pos = "center",
    })
  else
    vim.cmd(style == "vsplit" and "vnew" or "new")
    bufnr = vim.api.nvim_get_current_buf()
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(text, "\n"))
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].modifiable = false
end

return M
