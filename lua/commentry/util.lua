local M = {}

---@param msg string|string[]
---@param level? vim.log.levels
function M.notify(msg, level)
  msg = type(msg) == "table" and table.concat(msg, "\n") or msg
  vim.schedule(function()
    vim.notify(msg, level or vim.log.levels.INFO, { title = "Commentry" })
  end)
end

---@param msg string|string[]
function M.info(msg)
  M.notify(msg, vim.log.levels.INFO)
end

---@param msg string|string[]
function M.error(msg)
  M.notify(msg, vim.log.levels.ERROR)
end

---@param msg string|string[]
function M.warn(msg)
  M.notify(msg, vim.log.levels.WARN)
end

---@param msg string|string[]
---@param what? any
function M.debug(msg, what)
  if require("commentry.config").debug then
    if what ~= nil then
      msg = type(msg) == "table" and msg or { msg } ---@type string[]
      msg[#msg + 1] = "```lua"
      msg[#msg + 1] = vim.inspect(what)
      msg[#msg + 1] = "```"
    end
    M.warn(msg)
  end
end

---@class commentry.DiffHunkHeader
---@field base_start integer
---@field base_count integer
---@field head_start integer
---@field head_count integer

---@class commentry.DiffCounters
---@field base integer
---@field head integer

---@param line string
---@return commentry.DiffHunkHeader|nil
function M.parse_hunk_header(line)
  local base_start, base_count, head_start, head_count = line:match("^@@%s+%-(%d+),?(%d*)%s+%+(%d+),?(%d*)%s+@@")
  if not base_start then
    return nil
  end
  return {
    base_start = tonumber(base_start),
    base_count = tonumber(base_count) or 1,
    head_start = tonumber(head_start),
    head_count = tonumber(head_count) or 1,
  }
end

---@param header string|commentry.DiffHunkHeader
---@return commentry.DiffCounters|nil
function M.start_hunk_counters(header)
  local parsed = type(header) == "string" and M.parse_hunk_header(header) or header
  if not parsed then
    return nil
  end
  return { base = parsed.base_start, head = parsed.head_start }
end

---@param line string
---@return boolean
function M.is_diff_metadata(line)
  return line:match("^diff ")
    or line:match("^index ")
    or line:match("^@@")
    or line:match("^%-%-%-")
    or line:match("^%+%+%+")
    or line:match("^new file")
    or line:match("^deleted file")
    or line:match("^similarity index")
    or line:match("^rename from")
    or line:match("^rename to")
end

---@param line string
---@return '"add"'|'"del"'|'"ctx"'|'"meta"'|'"other"'
function M.diff_line_kind(line)
  if M.is_diff_metadata(line) then
    return "meta"
  end
  local first = line:sub(1, 1)
  if first == "+" then
    return "add"
  end
  if first == "-" then
    return "del"
  end
  if first == " " then
    return "ctx"
  end
  return "other"
end

---@param line string
---@param counters commentry.DiffCounters
---@param opts? { prefer: '"base"'|'"head"' }
---@return commentry.Anchor|nil, string
function M.diff_anchor_for_line(line, counters, opts)
  opts = opts or {}
  local kind = M.diff_line_kind(line)
  if kind == "add" then
    local anchor = { line_side = "head", line_number = counters.head }
    counters.head = counters.head + 1
    return anchor, kind
  end
  if kind == "del" then
    local anchor = { line_side = "base", line_number = counters.base }
    counters.base = counters.base + 1
    return anchor, kind
  end
  if kind == "ctx" then
    local prefer = opts.prefer == "base" and "base" or "head"
    local number = prefer == "base" and counters.base or counters.head
    local anchor = { line_side = prefer, line_number = number }
    counters.base = counters.base + 1
    counters.head = counters.head + 1
    return anchor, kind
  end
  return nil, kind
end

return M
