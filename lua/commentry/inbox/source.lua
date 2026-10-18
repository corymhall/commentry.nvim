local M = {}

local function relative(root, path)
  root = vim.fs.normalize(root):gsub("/$", "")
  path = vim.fs.normalize(path)
  if path:sub(1, #root + 1) == root .. "/" then
    return path:sub(#root + 2)
  end
end

local function git(root, args)
  local command = { "git", "-C", root }
  vim.list_extend(command, args)
  local result = vim.system(command, { text = true }):wait()
  return result.code == 0 and vim.trim(result.stdout) or nil
end

function M.project(directory)
  local path = vim.fs.normalize(vim.fn.fnamemodify(directory or vim.fn.getcwd(), ":p"))
  path = (vim.uv or vim.loop).fs_realpath(path) or path
  return git(path, { "rev-parse", "--show-toplevel" }) or (path == "/" and path or path:gsub("/$", ""))
end

function M.capture(bufnr, first, last)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" or vim.bo[bufnr].buftype ~= "" then
    return nil, "Capture requires a normal named file buffer; use capture-text for copied text"
  end
  local contents = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if first < 1 or last < first or last > #contents then
    return nil, "Invalid capture range"
  end
  local project = M.project(vim.fs.dirname(path))
  local relative_path = relative(project, path)
  if not relative_path then
    return nil, "File is outside the current project"
  end
  return {
    project = project,
    source = {
      kind = "file",
      path = relative_path,
      first = first,
      last = last,
      lines = contents,
      filetype = vim.bo[bufnr].filetype,
      modified = vim.bo[bufnr].modified,
      git = {
        head = git(project, { "rev-parse", "HEAD" }),
        branch = git(project, { "branch", "--show-current" }),
        blob = git(project, { "rev-parse", "HEAD:" .. relative_path }),
      },
    },
  }
end

local function slice(contents, first, last)
  local out = {}
  for i = math.max(1, first), math.min(#contents, last) do
    out[#out + 1] = contents[i]
  end
  return out
end

local function text(contents)
  return table.concat(contents, "\n") .. "\n"
end

local function current_lines(thread)
  local path = vim.fs.joinpath(thread.project, thread.source.path)
  -- Reject symlinks that now lead outside the captured project.
  local real = (vim.uv or vim.loop).fs_realpath(path)
  if real and not relative(thread.project, real) then
    return nil
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == path then
      return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    end
  end
  local ok, contents = pcall(vim.fn.readfile, path)
  return ok and contents or nil
end

-- Map boundaries through the full-file diff before extracting a focused region.
-- This handles insertions above the selection without comparing unrelated code.
local function map_line(line, hunks, ending)
  local offset = 0
  for _, hunk in ipairs(hunks) do
    local old, count, new, size = unpack(hunk)
    if count == 0 then
      if old < line or (ending and old == line) then
        offset = offset + size
      end
    elseif line < old then
      break
    elseif line < old + count then
      return math.max(1, new + (ending and math.max(0, size - 1) or 0))
    else
      offset = offset + size - count
    end
  end
  return math.max(1, line + offset)
end

function M.compare(thread, mode, context)
  context = context or 4
  local source = thread.source
  if mode == "agent" then
    local comparison = thread.comparisons[#thread.comparisons]
    if not comparison then
      return nil, "No agent comparison attached"
    end
    local diff = vim.diff(comparison.before, comparison.after, { result_type = "unified", ctxlen = context })
    return {
      lines = vim.split(diff == "" and comparison.after or diff, "\n", { plain = true }),
      label = "Agent comparison / " .. comparison.author .. " / " .. comparison.at .. " / " .. comparison.label,
      filetype = diff == "" and "text" or "diff",
      outdated = false,
    }
  end
  if source.kind ~= "file" then
    return { lines = source.lines, label = "Original capture / no file anchor", filetype = "text", outdated = false }
  end
  local first, last = math.max(1, source.first - context), math.min(#source.lines, source.last + context)
  local before = slice(source.lines, first, last)
  local current = current_lines(thread)
  if mode == "original" or not current then
    return {
      lines = before,
      label = "Original capture / " .. source.path .. ":" .. first .. "-" .. last,
      filetype = source.filetype or "text",
      outdated = current == nil,
      unavailable = current == nil,
      first = first,
    }
  end
  local hunks = vim.diff(text(source.lines), text(current), { result_type = "indices", algorithm = "histogram" })
  local outdated = false
  for _, hunk in ipairs(hunks) do
    if
      (hunk[2] > 0 and hunk[1] <= source.last and hunk[1] + hunk[2] > source.first)
      or (hunk[2] == 0 and hunk[1] >= source.first and hunk[1] < source.last)
    then
      outdated = true
    end
  end
  local after = slice(current, map_line(first, hunks), map_line(last, hunks, true))
  local diff = vim.diff(text(before), text(after), { result_type = "unified", ctxlen = context })
  return {
    lines = diff == "" and before or vim.split(diff, "\n", { plain = true }),
    label = (outdated and "Outdated / approximate diff / " or "Since comment / ")
      .. source.path
      .. ":"
      .. source.first
      .. "-"
      .. source.last,
    filetype = diff == "" and (source.filetype or "text") or "diff",
    outdated = outdated,
    first = first,
    current_first = map_line(first, hunks),
  }
end

return M
