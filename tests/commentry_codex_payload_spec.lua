---@module 'luassert'

local Payload = require("commentry.codex.payload")

describe("commentry.codex.payload", function()
  it("builds payload with required top-level sections", function()
    local payload = Payload.build_payload({ context_id = "ctx-1" }, {
      review_meta = { mode = "working_tree" },
      items = { { id = "c1" } },
      provenance = { root = "/tmp/project" },
    })

    assert.are.same("ctx-1", payload.context.context_id)
    assert.are.same("working_tree", payload.review_meta.mode)
    assert.are.same("c1", payload.items[1].id)
    assert.are.same("/tmp/project", payload.provenance.root)
  end)

  it("serializes byte-identically for identical inputs", function()
    local context = { context_id = "ctx-1", revisions = { "HEAD~1..HEAD" } }
    local opts = {
      review_meta = { mode = "commit_range" },
      items = {
        { id = "c2", body = "second" },
        { id = "c1", body = "first" },
      },
      provenance = { root = "/tmp/project", files = { "b.lua", "a.lua" } },
    }

    local payload_a = Payload.build_payload(context, opts)
    local payload_b = Payload.build_payload(context, opts)

    assert.are.same(Payload.serialize(payload_a), Payload.serialize(payload_b))
  end)

  it("does not perform store or filesystem writes while building payload", function()
    local Store = require("commentry.store")
    local original_store_write = Store.write
    local original_writefile = vim.fn.writefile
    local store_write_calls = 0
    local writefile_calls = 0

    Store.write = function(...)
      store_write_calls = store_write_calls + 1
      return original_store_write(...)
    end
    vim.fn.writefile = function(...)
      writefile_calls = writefile_calls + 1
      return original_writefile(...)
    end

    local payload = Payload.build_payload({ context_id = "ctx-1" }, {
      items = { { id = "c1", body = "draft" } },
    })
    Payload.serialize(payload)

    Store.write = original_store_write
    vim.fn.writefile = original_writefile

    assert.are.same(0, store_write_calls)
    assert.are.same(0, writefile_calls)
  end)
end)
