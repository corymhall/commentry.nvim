-- Neovim owns capture and presentation. All persisted state belongs to the Go
-- backend so agents and the editor share the same transactions and validation.
local M = {}

function M.directory(opts)
  return (opts and opts.directory) or vim.env.COMMENTRY_INBOX_DIR or (vim.fn.stdpath("data") .. "/commentry/inbox")
end

function M.executable()
  if vim.env.COMMENTRY_CLI and vim.env.COMMENTRY_CLI ~= "" then
    return vim.env.COMMENTRY_CLI
  end
  local script = vim.api.nvim_get_runtime_file("scripts/commentry-inbox", false)[1]
  local local_binary = script and (vim.fs.dirname(vim.fs.dirname(script)) .. "/bin/commentry")
  if local_binary and vim.fn.executable(local_binary) == 1 then
    return local_binary
  end
  return vim.fn.exepath("commentry")
end

local function request(input, opts)
  local executable = M.executable()
  if not executable or executable == "" then
    return nil, "Commentry backend is missing. Run mise run build or install the commentry binary"
  end
  local ok, result = pcall(function()
    return vim
      .system({ executable, "--directory", M.directory(opts), "rpc" }, {
        text = true,
        stdin = vim.json.encode(input),
      })
      :wait(15000)
  end)
  if not ok then
    return nil, tostring(result)
  end
  local decoded, response = pcall(vim.json.decode, result.stdout or "")
  if not decoded or type(response) ~= "table" then
    return nil, "Commentry backend failed: " .. (result.stderr or "Invalid JSON response")
  end
  if result.code ~= 0 or not response.ok then
    return nil, response.error or result.stderr or "Inbox request failed"
  end
  return response.result
end

function M.list(project, opts)
  return request({ action = "list", project = project }, opts)
end

function M.get(id, opts)
  return request({ action = "read", thread = id }, opts)
end

function M.create(input, opts)
  input = vim.deepcopy(input or {})
  if input.source and type(input.source.git) == "table" and vim.tbl_isempty(input.source.git) then
    input.source.git = vim.empty_dict()
  end
  input.action = "create"
  return request(input, opts)
end

function M.update(id, input, opts)
  input = vim.deepcopy(input or {})
  if input.kind == "create" or input.kind == "claim" then
    return nil, "Use create or claim to start threads or claim work"
  end
  input.action = input.kind == "read" and "read-state" or input.kind
  input.kind, input.thread = nil, id
  return request(input, opts)
end

function M.enqueue(id, message, opts)
  return request({ action = "queue", thread = id, message = message }, opts)
end

function M.claim(project, author, opts)
  return request({ action = "claim", project = project, author = author }, opts)
end

function M.revision(opts)
  return request({ action = "revision" }, opts)
end

return M
