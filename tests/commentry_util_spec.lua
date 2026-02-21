---@module 'luassert'

local Util = require("commentry.util")

describe("commentry.util diff helpers", function()
  it("parses hunk headers and counters", function()
    local header = Util.parse_hunk_header("@@ -10,2 +20,4 @@")
    assert.are.same({ base_start = 10, base_count = 2, head_start = 20, head_count = 4 }, header)

    local minimal = Util.parse_hunk_header("@@ -3 +5 @@")
    assert.are.same({ base_start = 3, base_count = 1, head_start = 5, head_count = 1 }, minimal)

    local counters = Util.start_hunk_counters("@@ -7,1 +9,3 @@")
    assert.are.same({ base = 7, head = 9 }, counters)

    assert.is_nil(Util.start_hunk_counters("not a header"))
  end)

  it("classifies diff line kinds", function()
    local meta_lines = {
      "diff --git a/file b/file",
      "index 123..456 100644",
      "@@ -1,1 +1,1 @@",
      "--- a/file",
      "+++ b/file",
      "new file mode 100644",
      "deleted file mode 100644",
      "similarity index 100%",
      "rename from old",
      "rename to new",
    }

    for _, line in ipairs(meta_lines) do
      assert.are.same("meta", Util.diff_line_kind(line))
    end

    assert.are.same("add", Util.diff_line_kind("+added"))
    assert.are.same("del", Util.diff_line_kind("-removed"))
    assert.are.same("ctx", Util.diff_line_kind(" unchanged"))
    assert.are.same("other", Util.diff_line_kind("?unknown"))
  end)

  it("anchors diff lines and increments counters", function()
    local counters = { base = 1, head = 10 }
    local anchor, kind = Util.diff_anchor_for_line("+added", counters)
    assert.are.same("add", kind)
    assert.are.same({ line_side = "head", line_number = 10 }, anchor)
    assert.are.same({ base = 1, head = 11 }, counters)

    counters = { base = 3, head = 7 }
    anchor, kind = Util.diff_anchor_for_line("-removed", counters)
    assert.are.same("del", kind)
    assert.are.same({ line_side = "base", line_number = 3 }, anchor)
    assert.are.same({ base = 4, head = 7 }, counters)

    counters = { base = 5, head = 8 }
    anchor, kind = Util.diff_anchor_for_line(" unchanged", counters)
    assert.are.same("ctx", kind)
    assert.are.same({ line_side = "head", line_number = 8 }, anchor)
    assert.are.same({ base = 6, head = 9 }, counters)

    counters = { base = 5, head = 8 }
    anchor, kind = Util.diff_anchor_for_line(" unchanged", counters, { prefer = "base" })
    assert.are.same("ctx", kind)
    assert.are.same({ line_side = "base", line_number = 5 }, anchor)
    assert.are.same({ base = 6, head = 9 }, counters)

    counters = { base = 2, head = 2 }
    anchor, kind = Util.diff_anchor_for_line("diff --git a/file b/file", counters)
    assert.is_nil(anchor)
    assert.are.same("meta", kind)
    assert.are.same({ base = 2, head = 2 }, counters)
  end)
end)
