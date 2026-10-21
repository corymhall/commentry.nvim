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
  if source.kind ~= "file" then
    return { lines = source.lines, label = "Original capture / no file anchor", filetype = "text", outdated = false }
  end
  if source.excerpt_first then
    local origin = source.excerpt_first
    local first = math.max(origin, source.first - context)
    local last = math.min(origin + #source.lines - 1, source.last + context)
    local before = slice(source.lines, first - origin + 1, last - origin + 1)
    local current = current_lines(thread)
    local target = current and M.locate(thread)
    if mode == "original" or not target then
      return {
        lines = before,
        first = first,
        filetype = source.filetype or "text",
        label = "Saved excerpt / " .. source.path .. ":" .. first .. "-" .. last,
        outdated = current == nil or (mode ~= "original" and target == nil),
        unavailable = current == nil,
        unlocated = current ~= nil and mode ~= "original" and target == nil,
      }
    end
    local current_first = math.max(1, target.first - (source.first - first))
    local after = slice(current, current_first, target.last + last - source.last)
    local diff = vim.diff(text(before), text(after), { result_type = "unified", ctxlen = context })
    local live = vim.deepcopy(source)
    live.lines, live.first, live.last, live.excerpt_first = current, target.first, target.last, nil
    return {
      lines = diff == "" and before or vim.split(diff, "\n", { plain = true }),
      first = first,
      current_first = current_first,
      current_source = live,
      label = "Saved excerpt -> current code",
      filetype = diff == "" and (source.filetype or "text") or "diff",
      changed = diff ~= "",
      outdated = false,
    }
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
    changed = diff ~= "",
    outdated = outdated,
    first = first,
    current_first = map_line(first, hunks),
    current_source = #current > 0 and vim.tbl_extend("force", source, {
      lines = current,
      first = math.min(#current, map_line(source.first, hunks)),
      last = math.min(#current, map_line(source.last, hunks, true)),
    }) or nil,
  }
end

-- Keep the chosen explanation first. New supporting evidence must not change
-- the first screen. Each section retains its own navigation coordinates.
function M.sections(thread, context)
  local sections, outdated = {}, false
  local function add(id, title, detail, comparison, source, collapsed)
    sections[#sections + 1] = {
      id = id,
      title = title,
      detail = detail,
      comparison = comparison,
      source = source,
      collapsed = collapsed or false,
    }
  end
  local comparisons = thread.comparisons or {}
  local primary = comparisons[1]
  for _, event in ipairs(comparisons) do
    if event.id == thread.primary_comparison then
      primary = event
      break
    end
  end
  local ordered = {}
  if primary then
    ordered[1] = primary
  end
  for _, event in ipairs(comparisons) do
    if event ~= primary then
      ordered[#ordered + 1] = event
    end
  end
  for index, event in ipairs(ordered) do
    local diff = vim.diff(event.before, event.after, { result_type = "unified", ctxlen = context or 4 })
    add(
      "comparison:" .. (event.id or index),
      (
        index > 1 and "Supporting comparison / "
        or thread.primary_comparison and "Primary comparison / "
        or "Saved comparison / "
      ) .. event.label,
      "Saved by " .. event.author .. " / " .. event.at:sub(1, 16):gsub("T", " "),
      {
        lines = vim.split(diff == "" and event.after or diff, "\n", { plain = true }),
        filetype = diff == "" and "text" or "diff",
      },
      nil,
      index > 1
    )
  end
  local locations = thread.attachments or {}
  if #locations == 0 and thread.source.kind == "file" then
    locations = { { id = "original", label = "Original capture", source = thread.source } }
  end
  local original_shown = false
  for _, location in ipairs(locations) do
    local located = vim.tbl_extend("force", thread, { source = location.source })
    local comparison = M.compare(located, "since", context)
    local source = location.source
    local title = comparison.unlocated and "Saved excerpt / "
      or comparison.unavailable and "Saved snapshot / "
      or comparison.changed and "Changed locally since attached / "
      or "Current code / "
    local detail = comparison.unlocated and "Location changed or ambiguous / "
      or comparison.unavailable and "File unavailable / "
      or comparison.changed and "Saved snapshot -> working tree / "
      or "Matches saved snapshot / "
    local target = comparison.current_source
    local path = source.path
      .. ":"
      .. (target and target.first or source.first)
      .. "-"
      .. (target and target.last or source.last)
    -- Plain live excerpts use current coordinates even when lines moved above.
    if comparison.current_first and not comparison.changed and not comparison.unavailable then
      comparison.first = comparison.current_first
    end
    add(
      "location:" .. location.id,
      title .. path,
      detail .. location.label,
      comparison,
      target or source,
      primary ~= nil
    )
    outdated = outdated or comparison.outdated
    if location.id == "original" and not comparison.changed then
      original_shown = true
    end
  end
  if not original_shown and (thread.source.kind == "file" or #thread.source.lines > 0) then
    local source = thread.source
    add(
      "original",
      "Original context" .. (source.path and " / " .. source.path or ""),
      "Captured when this conversation started",
      M.compare(thread, "original", context),
      source,
      source.kind == "file" or #source.lines > 6
    )
  end
  if #sections == 0 then
    add("empty", "Project conversation", "No code or excerpt attached", { lines = {}, filetype = "text" })
  end
  return sections, outdated
end

-- Attachments share capture comparison logic, but never replace thread.source.
function M.locations(thread)
  local locations = {}
  for _, attachment in ipairs(thread.attachments or {}) do
    locations[#locations + 1] = attachment
  end
  if thread.source.kind == "file" or #thread.source.lines > 0 or #locations == 0 then
    locations[#locations + 1] = { id = "original", label = "Original capture", source = thread.source }
  end
  return locations
end

function M.with_location(thread, id)
  local locations = M.locations(thread)
  local location = locations[1]
  for _, item in ipairs(locations) do
    if item.id == id then
      location = item
    end
  end
  return vim.tbl_extend("force", thread, { source = location.source }), location
end

-- Only navigate when the selected code survives unchanged. Modified or missing
-- selections stay available as snapshots instead of guessing a destination.
function M.locate(thread)
  if thread.source.kind ~= "file" then
    return nil, "This item has no code location"
  end
  local current = current_lines(thread)
  if not current then
    return nil, "Outdated location: file unavailable"
  end
  local source = thread.source
  if source.excerpt_first then
    local function unique(block)
      local found
      if #block == 0 then
        return nil
      end
      for start = 1, #current - #block + 1 do
        if vim.deep_equal(slice(current, start, start + #block - 1), block) then
          if found then
            return nil
          end
          found = start
        end
      end
      return found
    end
    local start = unique(source.lines)
    local first = start and (start + source.first - source.excerpt_first)
    if not first then
      first =
        unique(slice(source.lines, source.first - source.excerpt_first + 1, source.last - source.excerpt_first + 1))
    end
    if first then
      return {
        path = vim.fs.joinpath(thread.project, source.path),
        first = first,
        last = first + source.last - source.first,
      }
    end
    return nil, "Outdated location: selected excerpt changed or is ambiguous"
  end
  local hunks = vim.diff(text(source.lines), text(current), { result_type = "indices", algorithm = "histogram" })
  local first, last = map_line(source.first, hunks), map_line(source.last, hunks, true)
  if
    last - first == source.last - source.first
    and vim.deep_equal(slice(current, first, last), slice(source.lines, source.first, source.last))
  then
    return { path = vim.fs.joinpath(thread.project, source.path), first = first, last = last }
  end
  -- A block may have moved across other code. Accept a unique exact match.
  local matches = {}
  for start = 1, #current - (source.last - source.first) do
    if
      vim.deep_equal(
        slice(current, start, start + source.last - source.first),
        slice(source.lines, source.first, source.last)
      )
    then
      matches[#matches + 1] = start
    end
  end
  if #matches == 1 then
    return {
      path = vim.fs.joinpath(thread.project, source.path),
      first = matches[1],
      last = matches[1] + source.last - source.first,
    }
  end
  return nil, "Outdated location: selected code changed or is ambiguous"
end

return M
