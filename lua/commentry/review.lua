local M = {}

local uv = vim.uv or vim.loop

local function run_git(root, args, stdin)
  local cmd = { "git", "-C", root }
  vim.list_extend(cmd, args)
  local result = vim.system(cmd, { text = false, stdin = stdin }):wait()
  if result.code ~= 0 then
    local message = type(result.stderr) == "string" and vim.trim(result.stderr) or ""
    return nil, message ~= "" and message or "git command failed"
  end
  return result.stdout or "", nil
end

local function nul_records(output)
  local records = {}
  for record in output:gmatch("([^%z]+)%z") do
    records[#records + 1] = record
  end
  return records
end

local function commit_entries(root, commit, paths)
  if #paths == 0 then
    return {}, nil
  end
  local args = { "ls-tree", "-z", commit, "--" }
  vim.list_extend(args, paths)
  local output, err = run_git(root, args)
  if not output then
    return nil, err
  end
  local entries = {}
  for _, record in ipairs(nul_records(output)) do
    local mode, oid, path = record:match("^(%d+)%s+%S+%s+(%x+)\t(.*)$")
    if mode and oid and path then
      entries[path] = { mode = mode, oid = oid:lower() }
    end
  end
  return entries, nil
end

local function stage_entries(root, requests)
  if #requests == 0 then
    return {}, nil
  end
  local paths = {}
  local seen = {}
  for _, request in ipairs(requests) do
    if not seen[request.path] then
      seen[request.path] = true
      paths[#paths + 1] = request.path
    end
  end
  local args = { "ls-files", "--stage", "-z", "--" }
  vim.list_extend(args, paths)
  local output, err = run_git(root, args)
  if not output then
    return nil, err
  end
  local entries = {}
  for _, record in ipairs(nul_records(output)) do
    local mode, oid, stage, path = record:match("^(%d+)%s+(%x+)%s+(%d+)\t(.*)$")
    if mode and oid and stage and path then
      entries[("%s\31%s"):format(stage, path)] = { mode = mode, oid = oid:lower() }
    end
  end
  return entries, nil
end

local function core_filemode(root)
  local output = run_git(root, { "config", "--bool", "core.filemode" })
  if type(output) ~= "string" then
    return true
  end
  return vim.trim(output) ~= "false"
end

local function executable(mode)
  if type(mode) ~= "number" then
    return false
  end
  local permissions = mode % 512
  return permissions % 2 >= 1 or math.floor(permissions / 8) % 2 >= 1 or math.floor(permissions / 64) % 2 >= 1
end

local function local_entries(root, paths, index_entries)
  local entries = {}
  local hash_paths = {}
  local hash_stats = {}
  local honor_filemode = core_filemode(root)

  for _, path in ipairs(paths) do
    local absolute = vim.fs.joinpath(root, path)
    local stat = uv.fs_lstat(absolute)
    if stat then
      local index = index_entries[("0\31%s"):format(path)]
      if index and index.mode == "160000" and stat.type == "directory" then
        local output = run_git(absolute, { "rev-parse", "HEAD" })
        local oid = type(output) == "string" and vim.trim(output):lower() or nil
        if oid and oid:match("^%x+$") then
          entries[path] = { mode = "160000", oid = oid }
        end
      else
        hash_paths[#hash_paths + 1] = path
        hash_stats[path] = { stat = stat, index = index }
      end
    end
  end

  if #hash_paths > 0 then
    local args = { "hash-object", "--" }
    vim.list_extend(args, hash_paths)
    local output, err = run_git(root, args)
    if not output then
      return nil, err
    end
    local hashes = vim.split(vim.trim(output), "\n", { plain = true, trimempty = true })
    if #hashes ~= #hash_paths then
      return nil, "git hash-object returned an unexpected number of hashes"
    end
    for index, path in ipairs(hash_paths) do
      local metadata = hash_stats[path]
      local mode
      if metadata.stat.type == "link" then
        mode = "120000"
      elseif not honor_filemode and metadata.index then
        mode = metadata.index.mode
      else
        mode = executable(metadata.stat.mode) and "100755" or "100644"
      end
      entries[path] = { mode = mode, oid = hashes[index]:lower() }
    end
  end

  return entries, nil
end

local function rev_kind(rev)
  if type(rev) ~= "table" then
    return nil
  end
  if type(rev.commit) == "string" and rev.commit ~= "" then
    return "commit"
  end
  if type(rev.stage) == "number" then
    return "stage"
  end
  if rev.kind == "local" or rev.kind == "LOCAL" or tostring(rev) == "LOCAL" then
    return "local"
  end
  local ok, rev_module = pcall(require, "diffview.vcs.rev")
  if ok and type(rev_module) == "table" and rev.type == rev_module.RevType.LOCAL then
    return "local"
  end
  return nil
end

local function endpoint_key(endpoint)
  if not endpoint then
    return "absent"
  end
  return ("%s:%s"):format(endpoint.mode, endpoint.oid)
end

local function is_absent(entry, side)
  if side == "base" then
    return entry.status == "A" or entry.status == "?"
  end
  return entry.status == "D"
end

local function request_for(entry, side)
  if is_absent(entry, side) then
    return { kind = "absent" }
  end
  local symbol = side == "base" and "a" or "b"
  local rev = type(entry.revs) == "table" and entry.revs[symbol] or nil
  local kind = rev_kind(rev)
  if not kind then
    return nil, ("unsupported %s revision for %s"):format(side, tostring(entry.path))
  end
  local path = side == "base" and (entry.oldpath or entry.path) or entry.path
  local layout = type(entry.layout) == "table" and entry.layout or nil
  local slot = layout and layout[symbol] or nil
  local file = type(slot) == "table" and slot.file or nil
  local bufnr = type(file) == "table" and file.bufnr or nil
  if
    type(bufnr) ~= "number"
    or not vim.api.nvim_buf_is_valid(bufnr)
    or not vim.api.nvim_buf_is_loaded(bufnr)
    or not vim.bo[bufnr].modified
  then
    bufnr = nil
  end
  return {
    kind = kind,
    path = path,
    commit = rev.commit,
    stage = rev.stage,
    bufnr = bufnr,
  }, nil
end

local function buffer_endpoint(root, request, endpoint)
  if type(request.bufnr) ~= "number" or type(endpoint) ~= "table" then
    return endpoint
  end
  local lines = vim.api.nvim_buf_get_lines(request.bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")
  if vim.bo[request.bufnr].endofline then
    content = content .. "\n"
  end
  local args = { "hash-object" }
  if request.kind == "local" then
    args[#args + 1] = "--path=" .. request.path
  end
  args[#args + 1] = "--stdin"
  local output = run_git(root, args, content)
  local oid = type(output) == "string" and vim.trim(output):lower() or nil
  if not oid or oid:match("^%x+$") == nil then
    return endpoint
  end
  return { mode = endpoint.mode, oid = oid }
end

---@param root string
---@param entries table[]
---@return table<table, table>, string[]
function M.snapshots(root, entries)
  local requests = {}
  local commit_paths = {}
  local stage_requests = {}
  local local_paths = {}
  local local_seen = {}
  local errors = {}

  for _, entry in ipairs(entries or {}) do
    if type(entry) == "table" and type(entry.path) == "string" and entry.path ~= "" then
      local base, base_err = request_for(entry, "base")
      local head, head_err = request_for(entry, "head")
      if base and head then
        requests[entry] = { base = base, head = head }
        for _, request in ipairs({ base, head }) do
          if request.kind == "commit" then
            commit_paths[request.commit] = commit_paths[request.commit] or {}
            commit_paths[request.commit][request.path] = true
          elseif request.kind == "stage" then
            stage_requests[#stage_requests + 1] = request
          elseif request.kind == "local" and not local_seen[request.path] then
            local_seen[request.path] = true
            local_paths[#local_paths + 1] = request.path
            stage_requests[#stage_requests + 1] = { path = request.path, stage = 0 }
          end
        end
      else
        errors[#errors + 1] = base_err or head_err
      end
    end
  end

  local commits = {}
  for commit, path_set in pairs(commit_paths) do
    local paths = vim.tbl_keys(path_set)
    table.sort(paths)
    local resolved, err = commit_entries(root, commit, paths)
    if resolved then
      commits[commit] = resolved
    else
      errors[#errors + 1] = err
    end
  end

  local stages, stage_err = stage_entries(root, stage_requests)
  if not stages then
    stages = {}
    errors[#errors + 1] = stage_err
  end

  local locals, local_err = local_entries(root, local_paths, stages)
  if not locals then
    locals = {}
    errors[#errors + 1] = local_err
  end

  local function resolve(request)
    local endpoint
    if request.kind == "absent" then
      return nil, true
    elseif request.kind == "commit" then
      endpoint = commits[request.commit] and commits[request.commit][request.path] or nil
    elseif request.kind == "stage" then
      endpoint = stages[("%d\31%s"):format(request.stage, request.path)]
    elseif request.kind == "local" then
      endpoint = locals[request.path]
    else
      return nil, false
    end
    return buffer_endpoint(root, request, endpoint), true
  end

  local snapshots = {}
  for entry, pair in pairs(requests) do
    local base, base_supported = resolve(pair.base)
    local head, head_supported = resolve(pair.head)
    if base_supported and head_supported then
      local base_key = endpoint_key(base)
      local head_key = endpoint_key(head)
      snapshots[entry] = {
        base = base_key,
        head = head_key,
        fingerprint = vim.fn.sha256(base_key .. "\0" .. head_key),
      }
    end
  end

  return snapshots, errors
end

return M
