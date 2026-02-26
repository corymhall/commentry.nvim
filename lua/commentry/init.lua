local M = {}

---@param opts? commentry.Config
function M.setup(opts)
  local Config = require("commentry.config")
  Config.setup(opts)
  require("commentry.commands").setup()
  require("commentry.diffview").setup()

  if Config.codex and Config.codex.enabled then
    local ok, codex = pcall(require, "commentry.codex")
    if ok and type(codex.setup) == "function" then
      codex.setup()
    end
  end
end

return M
