local Render = require("commentry.inbox.render")
local Source = require("commentry.inbox.source")

describe("inbox comparison collection", function()
  it("renders every attached diff with its label and independent line numbers", function()
    local thread = { title = "Review these changes", source = { kind = "text", lines = {} }, comparisons = {} }
    for index = 1, 10 do
      thread.comparisons[index] = {
        label = "File " .. index,
        author = "Agent",
        at = "2026-10-19T12:00:00Z",
        before = "old " .. index .. "\n",
        after = "new " .. index .. "\n",
      }
    end
    local comparison = assert(Source.compare(thread, "agent"))
    local buf = vim.api.nvim_create_buf(false, true)
    local ok, err = pcall(function()
      Render.highlights()
      Render.source({ mode = "agent", source_buf = buf }, thread, comparison)
      local contents = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local text = table.concat(contents, "\n")
      for index = 1, 10 do
        assert.is_truthy(text:find(("Comparison %d/10 / File %d"):format(index, index), 1, true))
        assert.is_truthy(text:find("-old " .. index .. "\n+new " .. index, 1, true))
      end
      local added = 0
      local ns = vim.api.nvim_get_namespaces()["commentry.inbox.ui"]
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
        local row, detail = mark[2], mark[4]
        if contents[row + 1]:sub(1, 5) == "+new " and detail.virt_text then
          added = added + 1
          assert.is_truthy(detail.virt_text[1][1]:find("1", 1, true))
        end
      end
      assert.are.same(10, added)
    end)
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.is_true(ok, tostring(err))
  end)
end)
