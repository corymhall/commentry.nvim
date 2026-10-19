-- General agent actions for Rex. No Commentry, Neovim, or harness RPC dependency.
-- Load with dofile('/path/to/agents.lua').setup() from Rex init.lua.
local M = {}

local function call(method, args)
  local result, err = rex.call(method, args)
  if not result then
    error(err, 0)
  end
  return result
end

local function terminal(agent, method, args)
  return call("block.method", {
    session_id = agent.session,
    block_id = agent.block,
    method = method,
    args = args or {},
  })
end

local function kind(value, adapters)
  local name = (value or ""):match("([^/]+)$")
  return adapters[name] and name or nil
end

local function inspect(session, block, window, adapters)
  local location = { session = session, block = block }
  local process = terminal(location, "process").foreground
  if not process then
    return
  end
  local status = terminal(location, "program_status")
  local state, harness = "unknown", kind(process.name, adapters)
  -- A root record from the foreground process identifies the agent's own UI.
  -- Child workers and records retained after exit do not indicate readiness.
  for _, record in ipairs(status.records or {}) do
    if (not record.id or record.id == "") and record.owner and record.owner.pid == process.pid then
      harness = kind(record.effective_app or record.app, adapters) or harness
      state = record.state
    end
  end
  if not harness then
    return
  end
  return {
    id = session .. "/" .. block .. "/" .. process.pid,
    session = session,
    block = block,
    window = window,
    pid = process.pid,
    harness = harness,
    state = state,
    cwd = process.cwd,
    name = harness .. " / " .. (process.cwd or block),
  }
end

function M.list(args, adapters)
  local agents, errors = {}, {}
  for _, session in ipairs(call("session.list", {}).sessions or {}) do
    local ok, attached = pcall(call, "session.attach", { session_id = session.session_id })
    if ok then
      for _, window in ipairs(attached.view.windows or {}) do
        for _, layer in ipairs(window.layers or {}) do
          for _, block in ipairs(layer.blocks or {}) do
            if block.creator_name == "com.superlogical.terminal" then
              local valid, agent = pcall(inspect, session.session_id, block.block_id, window.window_id, adapters)
              if valid and agent then
                local project = args.project and args.project:gsub("/+$", "")
                if not project or agent.cwd == project or (agent.cwd or ""):sub(1, #project + 1) == project .. "/" then
                  agents[#agents + 1] = agent
                end
              elseif not valid then
                errors[#errors + 1] = tostring(agent)
              end
            end
          end
        end
      end
    else
      errors[#errors + 1] = tostring(attached)
    end
  end
  -- Rex serializes an empty Lua table as {}, so omit empty arrays.
  return { agents = #agents > 0 and agents or nil, errors = #errors > 0 and errors or nil }
end

local function target(args, adapters)
  local found
  for _, agent in ipairs(M.list({}, adapters).agents or {}) do
    if agent.id == args.target or agent.block == args.target then
      if found then
        error("Ambiguous agent target; use its full ID", 0)
      end
      found = agent
    end
  end
  if not found then
    error("Agent is no longer in that pane; list agents and select it again", 0)
  end
  return found
end

local function send(args, mode, adapters)
  local text = args.text:gsub("\r\n", "\n")
  if text:match("^%s*$") or #text > 1024 * 1024 then
    error("Message must contain text and be at most 1 MiB", 0)
  end
  if text:find("[%z\1-\8\11-\31\127]") then
    error("Message contains terminal control characters", 0)
  end
  local agent = target(args, adapters)
  if agent.state ~= "working" and agent.state ~= "idle" and agent.state ~= "done" then
    error("Agent needs attention before delivery: " .. agent.state, 0)
  end
  local adapter = adapters[agent.harness]
  -- Send one bracketed paste and the native submission key in one PTY write.
  -- The harness owns scheduling. Queue delivery never waits for idle here.
  local data = "\27[200~" .. text .. "\27[201~" .. adapter[mode]
  local result = terminal(agent, "write", { data = data })
  if result.bytes_written ~= #data then
    error("Delivery may be partial; inspect the agent before resubmitting", 0)
  end
  return { target = agent.id, mode = mode, submitted = true }
end

function M.setup(options)
  options = options or {}
  -- Override byte sequences here when an agent uses customized keybindings.
  local adapters = options.adapters
    or {
      codex = { queue = "\t", steer = "\r" },
      pi = { queue = "\27\r", steer = "\r" },
    }
  for name, adapter in pairs(adapters) do
    if type(adapter.queue) ~= "string" or type(adapter.steer) ~= "string" then
      error("Agent adapter " .. name .. " requires queue and steer key sequences")
    end
  end
  rex.action({
    name = "agent_list",
    title = "List Running Agents",
    args = { project = "string?" },
    run = function(_, args)
      return M.list(args, adapters)
    end,
  })
  rex.action({
    name = "agent_get",
    title = "Inspect Agent",
    args = { target = "string" },
    run = function(_, args)
      return target(args, adapters)
    end,
  })
  for _, mode in ipairs({ "queue", "steer" }) do
    local delivery_mode = mode
    rex.action({
      name = "agent_" .. mode,
      title = mode == "queue" and "Queue Message for Agent" or "Steer Agent",
      args = { target = "string", text = "string" },
      run = function(_, args)
        return send(args, delivery_mode, adapters)
      end,
    })
  end
  rex.action({
    name = "agent_read",
    title = "Read Agent Terminal",
    args = { target = "string" },
    run = function(_, args)
      return terminal(target(args, adapters), "format", { format = "text", unwrap = true })
    end,
  })
  rex.action({
    name = "agent_focus",
    title = "Focus Existing Agent",
    args = { target = "string" },
    run = function(_, args)
      local agent = target(args, adapters)
      call("session.focus_block", { session_id = agent.session, block_id = agent.block })
      rex.client.queue("session.select", { session_id = agent.session, window_id = agent.window })
      return agent
    end,
  })
end

return M
