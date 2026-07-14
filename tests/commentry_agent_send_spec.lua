---@module 'luassert'

local function load_send_with_stubs(stubs)
  local original_config = package.loaded["commentry.config"]
  local original_diffview = package.loaded["commentry.diffview"]
  local original_comments = package.loaded["commentry.comments"]
  local original_payload = package.loaded["commentry.agent.payload"]
  local original_adapter = package.loaded["commentry.agent.adapter"]
  local original_sidekick = package.loaded["commentry.agent.adapters.sidekick"]
  local original_sidekick_preload = package.preload["commentry.agent.adapters.sidekick"]
  local original_send = package.loaded["commentry.agent.send"]

  package.loaded["commentry.config"] = stubs.config
  package.loaded["commentry.diffview"] = stubs.diffview
  package.loaded["commentry.comments"] = stubs.comments
  package.loaded["commentry.agent.payload"] = stubs.payload
  package.loaded["commentry.agent.adapter"] = stubs.adapter
  package.loaded["commentry.agent.adapters.sidekick"] = stubs.sidekick
  package.preload["commentry.agent.adapters.sidekick"] = function()
    return stubs.sidekick
  end
  package.loaded["commentry.agent.send"] = nil

  local send = require("commentry.agent.send")

  package.loaded["commentry.config"] = original_config
  package.loaded["commentry.diffview"] = original_diffview
  package.loaded["commentry.comments"] = original_comments
  package.loaded["commentry.agent.payload"] = original_payload
  package.loaded["commentry.agent.adapter"] = original_adapter
  package.loaded["commentry.agent.adapters.sidekick"] = original_sidekick
  package.preload["commentry.agent.adapters.sidekick"] = original_sidekick_preload
  package.loaded["commentry.agent.send"] = original_send

  return send
end

local function adapter_error(code)
  local errors = {
    NO_TARGET = { code = "NO_TARGET", message = "No target adapter configured.", retryable = false },
    ADAPTER_UNAVAILABLE = {
      code = "ADAPTER_UNAVAILABLE",
      message = "Target adapter is unavailable.",
      retryable = true,
    },
    TRANSPORT_FAILED = { code = "TRANSPORT_FAILED", message = "Adapter transport failed.", retryable = true },
    INTERNAL_ERROR = { code = "INTERNAL_ERROR", message = "Internal adapter error.", retryable = false },
  }
  return vim.deepcopy(errors[code] or errors.INTERNAL_ERROR)
end

local function standard_stubs(overrides)
  local stubs = {
    config = {
      agent = { enabled = true },
    },
    diffview = {
      current_file_context = function()
        return {
          file_path = "a.lua",
          line_number = 3,
          line_side = "head",
          view = { id = "view-1" },
        },
          nil
      end,
      resolve_review_context = function()
        return {
          context_id = "ctx-diffview",
          mode = "working_tree",
          root = "/tmp/project",
        },
          nil
      end,
    },
    comments = {
      context_id_for_view = function()
        return "ctx-comments", nil
      end,
      reconcile_review = function()
        return true
      end,
      exportable_comments = function(context_id)
        return {
          {
            id = "c-1",
            diff_id = context_id,
            body = "draft",
            file_path = "a.lua",
            line_number = 3,
            line_side = "head",
          },
        }
      end,
    },
    payload = {
      build_payload = function(context, opts)
        return { context = context, items = opts.items }
      end,
    },
    adapter = {
      error = adapter_error,
      send = function(payload, target)
        return target.send(payload, target)
      end,
    },
    sidekick = {
      send = function(payload)
        return true, nil, { delegated = true, dispatched_items = #payload.items }
      end,
    },
  }
  return vim.tbl_deep_extend("force", stubs, overrides or {})
end

describe("commentry.agent.send", function()
  it("delegates the current review with the comments context id", function()
    local seen_context_id = nil
    local seen_target = nil
    local stubs = standard_stubs({
      comments = {
        exportable_comments = function(context_id)
          seen_context_id = context_id
          return {
            {
              id = "c-1",
              diff_id = context_id,
              body = "draft",
              file_path = "a.lua",
              line_number = 3,
              line_side = "head",
            },
          }
        end,
      },
      sidekick = {
        send = function(payload, target)
          seen_target = target
          return true, nil, { delegated = true, dispatched_items = #payload.items }
        end,
      },
    })
    local send = load_send_with_stubs(stubs)

    local result = send.send_current_review({})

    assert.are.same("ctx-comments", seen_context_id)
    assert.is_nil(seen_target.harness)
    assert.is_true(result.ok)
    assert.is_true(result.delegated)
    assert.are.same(1, result.dispatched_items)
  end)

  it("fails before delegation outside an active review context", function()
    local sidekick_calls = 0
    local send = load_send_with_stubs(standard_stubs({
      diffview = {
        current_file_context = function()
          return nil, "current buffer is not a diffview file buffer"
        end,
      },
      sidekick = {
        send = function()
          sidekick_calls = sidekick_calls + 1
          return true, nil, {}
        end,
      },
    }))

    local result = send.send_current_review({})

    assert.are.same({
      ok = false,
      code = "INTERNAL_ERROR",
      message = "current buffer is not a diffview file buffer",
      retryable = false,
    }, result)
    assert.are.same(0, sidekick_calls)
  end)

  it("preserves normalized Sidekick transport failures", function()
    local send = load_send_with_stubs(standard_stubs({
      sidekick = {
        send = function()
          return false, adapter_error("TRANSPORT_FAILED")
        end,
      },
    }))

    local result = send.send_current_review({})

    assert.is_false(result.ok)
    assert.are.same("TRANSPORT_FAILED", result.code)
    assert.are.same("Adapter transport failed.", result.message)
    assert.is_true(result.retryable)
  end)

  it("ignores caller-supplied target identity", function()
    local seen_target = nil
    local send = load_send_with_stubs(standard_stubs({
      sidekick = {
        send = function(payload, target)
          seen_target = target
          return true, nil, { delegated = true, dispatched_items = #payload.items }
        end,
      },
    }))

    local result = send.send_current_review({
      target = { session_id = "caller-session" },
    })

    assert.is_true(result.ok)
    assert.is_nil(seen_target.session_id)
  end)

  it("supports the async command contract while Sidekick owns interactive selection", function()
    local send = load_send_with_stubs(standard_stubs())
    local seen = nil

    send.send_current_review_async({}, function(result)
      seen = result
    end)

    assert.is_table(seen)
    assert.is_true(seen.ok)
    assert.is_true(seen.delegated)
  end)
end)
