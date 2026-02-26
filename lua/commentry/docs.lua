local M = {}

--- update.
function M.update()
  vim.notify("commentry docs generation is not configured yet", vim.log.levels.WARN, { title = "Commentry" })
end

M.update()

return M
