local M = {}

---@param opts? commentry.Config
function M.setup(opts)
  require("commentry.config").setup(opts)
end

return M
