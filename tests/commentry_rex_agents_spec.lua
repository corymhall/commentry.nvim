---@module 'luassert'
describe("Rex agent actions", function()
  local previous, actions, writes, process, record, partial
  before_each(function()
    previous = _G.rex
    actions, writes = {}, {}
    partial = false
    process = { pid = 123, name = "codex", cwd = "/project" }
    record = { app = "codex", owner = { pid = 123 }, state = "working" }
    _G.rex = {
      action = function(action)
        actions[action.name] = action.run
      end,
      call = function(method, args)
        if method == "session.list" then
          return { sessions = { { session_id = "session" } } }
        elseif method == "session.attach" then
          return {
            view = {
              windows = {
                {
                  window_id = "window",
                  layers = { { blocks = { { block_id = "block", creator_name = "com.superlogical.terminal" } } } },
                },
              },
            },
          }
        elseif method == "block.method" then
          assert.are.same("session", args.session_id)
          assert.are.same("block", args.block_id)
          if args.method == "process" then
            return { foreground = process }
          elseif args.method == "program_status" then
            return { records = { record } }
          elseif args.method == "write" then
            writes[#writes + 1] = args.args.data
            return { bytes_written = #args.args.data - (partial and 1 or 0) }
          end
        end
        error("Unexpected Rex operation: " .. method)
      end,
    }
    dofile("integrations/rex/agents.lua").setup()
  end)
  after_each(function()
    _G.rex = previous
  end)

  it("delivers multiline native queues while agents are working", function()
    local id = actions.agent_list({}, {}).agents[1].id
    local result = actions.agent_queue({}, { target = id, text = "First line\nSecond line" })
    assert.is_true(result.submitted)
    assert.are.same("working", record.state)
    assert.are.same("\27[200~First line\nSecond line\27[201~\t", writes[1])
    process.name, record.app = "pi", "pi"
    actions.agent_queue({}, { target = id, text = "Pi follow-up" })
    assert.are.same("\27[200~Pi follow-up\27[201~\27\r", writes[2])
  end)

  it("uses direct submission for steering and allows native idle submission", function()
    local id = actions.agent_list({}, {}).agents[1].id
    actions.agent_steer({}, { target = id, text = "Change direction" })
    record.state = "idle"
    actions.agent_queue({}, { target = id, text = "Next task" })
    assert.are.same("\27[200~Change direction\27[201~\r", writes[1])
    assert.are.same("\27[200~Next task\27[201~\t", writes[2])
  end)

  it("does not submit into approval dialogs or replacement processes", function()
    local id = actions.agent_list({}, {}).agents[1].id
    record.state = "blocked"
    assert.has_error(function()
      actions.agent_queue({}, { target = id, text = "Task" })
    end)
    process.pid = 456
    record.owner.pid, record.state = 456, "working"
    assert.has_error(function()
      actions.agent_steer({}, { target = id, text = "Old task" })
    end)
    assert.are.same({}, writes)
  end)

  it("ignores stale status records after an agent exits to a shell", function()
    process.pid, process.name = 456, "zsh"
    assert.is_nil(actions.agent_list({}, {}).agents)
    process.pid, process.name = 123, "codex"
    record.id = "background-worker"
    local agent = actions.agent_list({}, {}).agents[1]
    assert.are.same("unknown", agent.state)
    assert.has_error(function()
      actions.agent_queue({}, { target = agent.id, text = "Task" })
    end)
    assert.are.same({}, writes)
  end)

  it("rejects paste escapes before writing and exposes partial delivery", function()
    local id = actions.agent_list({}, {}).agents[1].id
    assert.has_error(function()
      actions.agent_queue({}, { target = id, text = "Escape \27[201~in payload" })
    end)
    assert.are.same({}, writes)
    partial = true
    assert.has_error(function()
      actions.agent_queue({}, { target = id, text = "Task" })
    end)
    assert.are.same(1, #writes)
  end)
end)
