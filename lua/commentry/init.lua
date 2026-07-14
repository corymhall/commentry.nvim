local M = {}

---@param opts? commentry.Config
function M.setup(opts)
  local Config = require("commentry.config")
  Config.setup(opts)
  require("commentry.log").setup(Config.log)
  require("commentry.commands").setup()
  require("commentry.diffview").setup()
end

return M
