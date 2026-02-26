---@class commentry.CodexError
---@field code "NO_TARGET"|"ADAPTER_UNAVAILABLE"|"TRANSPORT_FAILED"|"INTERNAL_ERROR"
---@field message string
---@field retryable boolean

local M = {}

local canonical_errors = {
  NO_TARGET = {
    code = "NO_TARGET",
    message = "No target adapter configured.",
    retryable = false,
  },
  ADAPTER_UNAVAILABLE = {
    code = "ADAPTER_UNAVAILABLE",
    message = "Target adapter is unavailable.",
    retryable = true,
  },
  TRANSPORT_FAILED = {
    code = "TRANSPORT_FAILED",
    message = "Adapter transport failed.",
    retryable = true,
  },
  INTERNAL_ERROR = {
    code = "INTERNAL_ERROR",
    message = "Internal adapter error.",
    retryable = false,
  },
}

M.ERRORS = vim.deepcopy(canonical_errors)

---@param code string
---@return commentry.CodexError
function M.error(code)
  local canonical = canonical_errors[code] or canonical_errors.INTERNAL_ERROR
  return {
    code = canonical.code,
    message = canonical.message,
    retryable = canonical.retryable,
  }
end

---@param err any
---@param fallback? "NO_TARGET"|"ADAPTER_UNAVAILABLE"|"TRANSPORT_FAILED"|"INTERNAL_ERROR"
---@return commentry.CodexError
function M.normalize_error(err, fallback)
  if type(err) == "table" then
    local code = err.code
    if type(code) == "string" and canonical_errors[code] then
      return M.error(code)
    end
  end

  if fallback and canonical_errors[fallback] then
    return M.error(fallback)
  end

  return M.error("INTERNAL_ERROR")
end

---@param payload any
---@param target? table
---@return boolean ok, commentry.CodexError? err, table? details
function M.send(payload, target)
  if target == nil then
    return false, M.error("NO_TARGET")
  end

  if type(target) ~= "table" or type(target.send) ~= "function" then
    return false, M.error("ADAPTER_UNAVAILABLE")
  end

  local called, ok, err, details = pcall(target.send, payload, target)
  if not called then
    return false, M.error("INTERNAL_ERROR")
  end

  if ok then
    local success_details = details
    if success_details == nil and type(err) == "table" then
      success_details = err
    end
    return true, nil, success_details
  end

  return false, M.normalize_error(err, "INTERNAL_ERROR")
end

return M
