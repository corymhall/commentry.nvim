---@module 'luassert'

local function load_send_with_stubs(stubs)
  local original_config = package.loaded["commentry.config"]
  local original_diffview = package.loaded["commentry.diffview"]
  local original_comments = package.loaded["commentry.comments"]
  local original_payload = package.loaded["commentry.codex.payload"]
  local original_adapter = package.loaded["commentry.codex.adapter"]
  local original_sidekick = package.loaded["commentry.codex.adapters.sidekick"]
  local original_send = package.loaded["commentry.codex.send"]

  package.loaded["commentry.config"] = stubs.config
  package.loaded["commentry.diffview"] = stubs.diffview
  package.loaded["commentry.comments"] = stubs.comments
  package.loaded["commentry.codex.payload"] = stubs.payload
  package.loaded["commentry.codex.adapter"] = stubs.adapter
  package.loaded["commentry.codex.adapters.sidekick"] = stubs.sidekick
  package.loaded["commentry.codex.send"] = nil

  local send = require("commentry.codex.send")

  package.loaded["commentry.config"] = original_config
  package.loaded["commentry.diffview"] = original_diffview
  package.loaded["commentry.comments"] = original_comments
  package.loaded["commentry.codex.payload"] = original_payload
  package.loaded["commentry.codex.adapter"] = original_adapter
  package.loaded["commentry.codex.adapters.sidekick"] = original_sidekick
  package.loaded["commentry.codex.send"] = original_send

  return send
end

describe("commentry.codex.send", function()
  it("uses comments context id to scope current review payload", function()
    local seen_context_id = nil
    local seen_payload_context = nil
    local seen_view = nil
    local send = load_send_with_stubs({
      config = {
        codex = {
          adapter = {
            select = "sidekick",
            fallback = nil,
          },
        },
      },
      diffview = {
        current_file_context = function()
          return {
            file_path = "a.lua",
            line_number = 3,
            line_side = "head",
            view = { id = "view-1" },
          }, nil
        end,
        resolve_review_context = function(_, view)
          seen_view = view
          return {
            context_id = "ctx-diffview",
            mode = "working_tree",
            root = "/tmp/project",
          }, nil
        end,
      },
      comments = {
        context_id_for_view = function()
          return "ctx-comments", nil
        end,
        exportable_comments = function(context_id)
          seen_context_id = context_id
          return {
            { id = "c-1", diff_id = context_id, body = "draft", file_path = "a.lua", line_number = 3, line_side = "head" },
          }
        end,
      },
      payload = {
        build_payload = function(context, opts)
          seen_payload_context = context
          return {
            context = context,
            items = opts.items,
          }
        end,
      },
      adapter = {
        error = function(code)
          if code == "NO_TARGET" then
            return { code = "NO_TARGET", message = "No target adapter configured.", retryable = false }
          end
          return { code = "INTERNAL_ERROR", message = "Internal adapter error.", retryable = false }
        end,
        send = function()
          return true, nil, { dispatched_items = 1 }
        end,
      },
      sidekick = {
        send = function()
          return true, nil, { dispatched_items = 1 }
        end,
      },
    })

    local result = send.send_current_review({
      target = {
        session_id = "session-1",
      },
    })

    assert.are.same("view-1", seen_view.id)
    assert.are.same("ctx-comments", seen_context_id)
    assert.are.same("ctx-comments", seen_payload_context.context_id)
    assert.is_true(result.ok)
    assert.are.same("OK", result.code)
    assert.are.same(1, result.dispatched_items)
  end)

  it("blocks dispatch with NO_TARGET and actionable remediation when no target is configured", function()
    local adapter_send_calls = 0
    local send = load_send_with_stubs({
      config = {
        codex = {
          adapter = {
            select = "auto",
            fallback = nil,
          },
        },
      },
      diffview = {
        current_file_context = function()
          return {
            file_path = "a.lua",
            line_number = 3,
            line_side = "head",
            view = { id = "view-2" },
          }, nil
        end,
        resolve_review_context = function()
          return {
            context_id = "ctx-2",
            mode = "working_tree",
            root = "/tmp/project",
          }, nil
        end,
      },
      comments = {
        context_id_for_view = function()
          return "ctx-2", nil
        end,
        exportable_comments = function()
          return {}
        end,
      },
      payload = {
        build_payload = function(context, opts)
          return { context = context, items = opts.items }
        end,
      },
      adapter = {
        error = function(code)
          if code == "NO_TARGET" then
            return { code = "NO_TARGET", message = "No target adapter configured.", retryable = false }
          end
          return { code = "INTERNAL_ERROR", message = "Internal adapter error.", retryable = false }
        end,
        send = function()
          adapter_send_calls = adapter_send_calls + 1
          return true, nil, {}
        end,
      },
      sidekick = {
        send = function()
          return true, nil, {}
        end,
      },
    })

    local result = send.send_current_review({})
    assert.are.same({
      ok = false,
      code = "NO_TARGET",
      message = "No target adapter configured. Provide target.session_id or target.send.",
      retryable = false,
    }, result)
    assert.are.same(0, adapter_send_calls)
  end)

  it("returns success contract with target adapter and dispatched_items", function()
    local seen_target = nil
    local send = load_send_with_stubs({
      config = {
        codex = {
          adapter = {
            select = "sidekick",
            fallback = nil,
          },
        },
      },
      diffview = {
        current_file_context = function()
          return {
            file_path = "a.lua",
            line_number = 3,
            line_side = "head",
            view = { id = "view-3" },
          }, nil
        end,
        resolve_review_context = function()
          return {
            context_id = "ctx-3",
            mode = "working_tree",
            root = "/tmp/project",
          }, nil
        end,
      },
      comments = {
        context_id_for_view = function()
          return "ctx-3", nil
        end,
        exportable_comments = function(context_id)
          return {
            { id = "c1", diff_id = context_id, body = "a", file_path = "a.lua", line_number = 3, line_side = "head" },
            { id = "c2", diff_id = context_id, body = "b", file_path = "b.lua", line_number = 5, line_side = "head" },
          }
        end,
      },
      payload = {
        build_payload = function(context, opts)
          return { context = context, items = opts.items }
        end,
      },
      adapter = {
        error = function(code)
          if code == "NO_TARGET" then
            return { code = "NO_TARGET", message = "No target adapter configured.", retryable = false }
          end
          return { code = "INTERNAL_ERROR", message = "Internal adapter error.", retryable = false }
        end,
        send = function(_, target)
          seen_target = target
          return true, nil, { dispatched_items = 2 }
        end,
      },
      sidekick = {
        send = function()
          return true, nil, {}
        end,
      },
    })

    local result = send.send_current_review({
      target = {
        session_id = "session-3",
        workspace = "/tmp/project",
      },
    })

    assert.is_true(result.ok)
    assert.are.same("OK", result.code)
    assert.are.same("sidekick", result.adapter)
    assert.are.same(2, result.dispatched_items)
    assert.are.same({
      session_id = "session-3",
      workspace = "/tmp/project",
    }, result.target)
    assert.are.same("session-3", seen_target.session_id)
    assert.are.same("/tmp/project", seen_target.workspace)
    assert.is_function(seen_target.send)
  end)

  it("returns retryable transport failure contract for adapter failures", function()
    local send = load_send_with_stubs({
      config = {
        codex = {
          adapter = {
            select = "sidekick",
            fallback = nil,
          },
        },
      },
      diffview = {
        current_file_context = function()
          return {
            file_path = "a.lua",
            line_number = 3,
            line_side = "head",
            view = { id = "view-4" },
          }, nil
        end,
        resolve_review_context = function()
          return {
            context_id = "ctx-4",
            mode = "working_tree",
            root = "/tmp/project",
          }, nil
        end,
      },
      comments = {
        context_id_for_view = function()
          return "ctx-4", nil
        end,
        exportable_comments = function()
          return {}
        end,
      },
      payload = {
        build_payload = function(context, opts)
          return { context = context, items = opts.items }
        end,
      },
      adapter = {
        error = function(code)
          if code == "NO_TARGET" then
            return { code = "NO_TARGET", message = "No target adapter configured.", retryable = false }
          end
          return { code = "INTERNAL_ERROR", message = "Internal adapter error.", retryable = false }
        end,
        send = function()
          return false, {
            code = "TRANSPORT_FAILED",
            message = "Adapter transport failed.",
            retryable = true,
          }
        end,
      },
      sidekick = {
        send = function()
          return true, nil, {}
        end,
      },
    })

    local result = send.send_current_review({
      target = {
        session_id = "session-4",
      },
    })

    assert.is_false(result.ok)
    assert.are.same("TRANSPORT_FAILED", result.code)
    assert.are.same("Adapter transport failed.", result.message)
    assert.is_true(result.retryable)
  end)
end)
