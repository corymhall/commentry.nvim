local M = {}

local CELL_WIDTH = 9
local CELL_HEIGHT = 20
local WINDOW_PADDING_X = 12
local WINDOW_PADDING_Y = 18
local HEADER_HEIGHT = 26
local FLOAT_HEADER_HEIGHT = 34
local SVG_MARGIN = 20
local SCENE_BG = "#f4efe7"
local GRID_BG = "#fbf7f2"
local WINDOW_BG = "#fffdfa"
local BORDER = "#bda98b"
local TEXT = "#2a2118"
local MUTED = "#6d5d4b"
local CURSOR = "#d97706"
local LINE_NUMBER = "#98856f"

local TYPE_COLORS = {
  issue = "#d94841",
  suggestion = "#0f766e",
  praise = "#2f855a",
  note = "#946200",
}

local function shell_error(message)
  vim.api.nvim_echo({ { ("commentry ui capture: %s"):format(message), "ErrorMsg" } }, true, {})
end

local function ensure_directory(path)
  vim.fn.mkdir(path, "p")
end

local function write_file(path, contents)
  vim.fn.writefile(vim.split(contents, "\n", { plain = true }), path)
end

local function read_env(name, default)
  local value = vim.env[name]
  if type(value) ~= "string" or value == "" then
    return default
  end
  return value
end

local function escape_xml(text)
  return tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;")
end

local function trim_path(path)
  if type(path) ~= "string" or path == "" then
    return "[No Name]"
  end
  return vim.fn.fnamemodify(path, ":t")
end

local function accent_from_name(name)
  if type(name) ~= "string" then
    return TYPE_COLORS.note
  end
  local lower = name:lower()
  for key, color in pairs(TYPE_COLORS) do
    if lower:find(key, 1, true) then
      return color
    end
  end
  return TYPE_COLORS.note
end

local function flatten_chunks(chunks)
  if type(chunks) ~= "table" then
    return ""
  end
  local pieces = {}
  for _, chunk in ipairs(chunks) do
    if type(chunk) == "table" and type(chunk[1]) == "string" then
      pieces[#pieces + 1] = chunk[1]
    end
  end
  return table.concat(pieces, "")
end

local function mark_details_to_rows(extmarks)
  local rows = {}

  local function ensure_row(row)
    rows[row] = rows[row] or {
      labels = {},
      signs = {},
      overlays = {},
      line_hl = nil,
    }
    return rows[row]
  end

  for _, extmark in ipairs(extmarks or {}) do
    local row = extmark[2]
    local details = extmark[4] or {}
    local bucket = ensure_row(row)

    if type(details.sign_text) == "string" and details.sign_text ~= "" then
      bucket.signs[#bucket.signs + 1] = {
        text = details.sign_text,
        color = accent_from_name(details.sign_hl_group),
      }
    end

    if type(details.line_hl_group) == "string" then
      bucket.line_hl = accent_from_name(details.line_hl_group)
    end

    if type(details.virt_text) == "table" and #details.virt_text > 0 then
      local label = flatten_chunks(details.virt_text)
      if label ~= "" then
        bucket.labels[#bucket.labels + 1] = {
          text = label,
          align = details.virt_text_pos or "eol",
          color = accent_from_name(details.virt_text[1] and details.virt_text[1][2]),
        }
      end
    end

    if type(details.virt_lines) == "table" and #details.virt_lines > 0 then
      for _, virt_line in ipairs(details.virt_lines) do
        local text = flatten_chunks(virt_line)
        if text ~= "" then
          bucket.overlays[#bucket.overlays + 1] = {
            text = text,
            color = accent_from_name(virt_line[1] and virt_line[1][2]),
          }
        end
      end
    end
  end

  return rows
end

local function visible_window_rows(win, buf)
  local topline = vim.api.nvim_win_call(win, function()
    return vim.fn.line("w0")
  end)
  local botline = vim.api.nvim_win_call(win, function()
    return vim.fn.line("w$")
  end)

  local lines = vim.api.nvim_buf_get_lines(buf, topline - 1, botline, false)
  local extmarks = vim.api.nvim_buf_get_extmarks(buf, -1, { topline - 1, 0 }, { botline - 1, -1 }, { details = true })
  local details_by_row = mark_details_to_rows(extmarks)

  local rows = {}
  for index, line in ipairs(lines) do
    local row_number = topline + index - 1
    local detail = details_by_row[row_number - 1] or { labels = {}, signs = {}, overlays = {} }
    rows[#rows + 1] = {
      kind = "buffer",
      line_number = row_number,
      text = line,
      labels = detail.labels,
      signs = detail.signs,
      line_hl = detail.line_hl,
    }
    for _, overlay in ipairs(detail.overlays or {}) do
      rows[#rows + 1] = {
        kind = "overlay",
        text = overlay.text,
        color = overlay.color,
      }
    end
  end

  return rows
end

local function capture_window(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local cfg = vim.api.nvim_win_get_config(win)
  local row
  local col
  if cfg.relative ~= nil and cfg.relative ~= "" then
    row = math.floor(tonumber(cfg.row) or 0)
    col = math.floor(tonumber(cfg.col) or 0)
  else
    local pos = vim.api.nvim_win_get_position(win)
    row = pos[1]
    col = pos[2]
  end

  local width = cfg.width and cfg.width > 0 and cfg.width or vim.api.nvim_win_get_width(win)
  local height = cfg.height and cfg.height > 0 and cfg.height or vim.api.nvim_win_get_height(win)
  local ok_winbar, winbar = pcall(vim.api.nvim_get_option_value, "winbar", { scope = "local", win = win })
  local ok_cursor, cursor = pcall(vim.api.nvim_win_get_cursor, win)

  return {
    id = win,
    buffer = {
      id = buf,
      name = vim.api.nvim_buf_get_name(buf),
      filetype = vim.bo[buf].filetype,
      buftype = vim.bo[buf].buftype,
    },
    row = row,
    col = col,
    width = width,
    height = height,
    relative = cfg.relative ~= "" and cfg.relative or "normal",
    focusable = cfg.focusable ~= false,
    border = cfg.border,
    title = type(cfg.title) == "table" and flatten_chunks(cfg.title) or cfg.title,
    winbar = ok_winbar and winbar or "",
    cursor = ok_cursor and cursor or { 1, 0 },
    rows = visible_window_rows(win, buf),
  }
end

function M.capture_snapshot(name)
  local windows = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    windows[#windows + 1] = capture_window(win)
  end
  local relative_priority = {
    normal = 1,
    win = 2,
    cursor = 3,
    mouse = 3,
    editor = 4,
  }
  table.sort(windows, function(a, b)
    if a.relative ~= b.relative then
      return (relative_priority[a.relative] or 10) < (relative_priority[b.relative] or 10)
    end
    if a.row ~= b.row then
      return a.row < b.row
    end
    return a.col < b.col
  end)

  return {
    name = name,
    columns = vim.o.columns,
    lines = vim.o.lines,
    cwd = vim.fn.getcwd(),
    windows = windows,
  }
end

local function window_frame(window)
  local x = SVG_MARGIN + (window.col * CELL_WIDTH)
  local y = SVG_MARGIN + (window.row * CELL_HEIGHT)
  local width = window.width * CELL_WIDTH
  local height = window.height * CELL_HEIGHT
  return x, y, width, height
end

local function truncate(text, max_chars)
  if type(text) ~= "string" then
    return ""
  end
  if #text <= max_chars then
    return text
  end
  if max_chars <= 1 then
    return text:sub(1, max_chars)
  end
  return text:sub(1, max_chars - 1) .. "…"
end

local function row_y(base_y, index, header_offset)
  return base_y + header_offset + ((index - 1) * CELL_HEIGHT)
end

local function render_label(text, x, y, color)
  local width = math.max(46, (#text * 7) + 18)
  return table.concat({
    ('<rect x="%d" y="%d" width="%d" height="18" rx="9" fill="%s" fill-opacity="0.16" />'):format(
      x,
      y - 13,
      width,
      color
    ),
    ('<text x="%d" y="%d" fill="%s" font-size="11" font-family="Iosevka, SFMono-Regular, Menlo, monospace">%s</text>'):format(
      x + 10,
      y,
      color,
      escape_xml(text)
    ),
  }, "\n")
end

local function render_window(window)
  local x, y, width, height = window_frame(window)
  local is_float = window.relative ~= "normal"
  local header_height = is_float and FLOAT_HEADER_HEIGHT or HEADER_HEIGHT
  local accent = is_float and "#b45309" or BORDER
  local parts = {
    ('<g data-window="%d">'):format(window.id),
    ('<rect x="%d" y="%d" width="%d" height="%d" rx="12" fill="%s" stroke="%s" stroke-width="%d" />'):format(
      x,
      y,
      width,
      height,
      WINDOW_BG,
      accent,
      is_float and 2 or 1
    ),
    ('<rect x="%d" y="%d" width="%d" height="%d" rx="12" fill="%s" />'):format(x, y, width, header_height, GRID_BG),
  }

  local title = window.title
  if type(title) ~= "string" or title == "" then
    title = trim_path(window.buffer.name)
  end
  parts[#parts + 1] = ('<text x="%d" y="%d" fill="%s" font-size="13" font-weight="600" font-family="Avenir Next, ui-sans-serif, sans-serif">%s</text>'):format(
    x + WINDOW_PADDING_X,
    y + 18,
    TEXT,
    escape_xml(title)
  )

  if type(window.winbar) == "string" and window.winbar ~= "" then
    parts[#parts + 1] = ('<text x="%d" y="%d" fill="%s" font-size="11" font-family="Avenir Next, ui-sans-serif, sans-serif">%s</text>'):format(
      x + WINDOW_PADDING_X,
      y + 31,
      MUTED,
      escape_xml(truncate(window.winbar, math.max(12, window.width - 8)))
    )
  elseif window.buffer.filetype ~= "" then
    parts[#parts + 1] = ('<text x="%d" y="%d" fill="%s" font-size="11" font-family="Avenir Next, ui-sans-serif, sans-serif">%s</text>'):format(
      x + WINDOW_PADDING_X,
      y + 31,
      MUTED,
      escape_xml(window.buffer.filetype)
    )
  end

  local max_chars = math.max(10, math.floor((width - (WINDOW_PADDING_X * 2) - 36) / 7))
  local cursor_row = tonumber(window.cursor[1]) or 1

  for index, row in ipairs(window.rows or {}) do
    local text_y = row_y(y, index, header_height + WINDOW_PADDING_Y)
    if text_y > y + height - WINDOW_PADDING_Y then
      break
    end

    if row.kind == "buffer" then
      if row.line_hl then
        parts[#parts + 1] = ('<rect x="%d" y="%d" width="%d" height="%d" fill="%s" fill-opacity="0.10" />'):format(
          x + 6,
          text_y - 15,
          width - 12,
          CELL_HEIGHT,
          row.line_hl
        )
      end
      if row.line_number == cursor_row then
        parts[#parts + 1] = ('<rect x="%d" y="%d" width="%d" height="%d" fill="%s" fill-opacity="0.08" />'):format(
          x + 6,
          text_y - 15,
          width - 12,
          CELL_HEIGHT,
          CURSOR
        )
      end
      local sign_text = row.signs[1] and row.signs[1].text or ""
      local sign_color = row.signs[1] and row.signs[1].color or MUTED
      if sign_text ~= "" then
        parts[#parts + 1] = ('<text x="%d" y="%d" fill="%s" font-size="13" font-family="Iosevka, SFMono-Regular, Menlo, monospace">%s</text>'):format(
          x + 10,
          text_y,
          sign_color,
          escape_xml(sign_text)
        )
      end
      if type(row.line_number) == "number" then
        parts[#parts + 1] = ('<text x="%d" y="%d" fill="%s" font-size="11" font-family="Iosevka, SFMono-Regular, Menlo, monospace">%s</text>'):format(
          x + 26,
          text_y,
          LINE_NUMBER,
          escape_xml(("%2d"):format(row.line_number))
        )
      end
      parts[#parts + 1] = ('<text x="%d" y="%d" fill="%s" font-size="13" font-family="Iosevka, SFMono-Regular, Menlo, monospace">%s</text>'):format(
        x + 52,
        text_y,
        TEXT,
        escape_xml(truncate(row.text or "", max_chars))
      )
      if row.labels then
        local label_x = x + width - 88
        for label_index, label in ipairs(row.labels) do
          parts[#parts + 1] = render_label(
            truncate(label.text, math.max(8, math.floor(window.width * 0.35))),
            label_x,
            text_y,
            label.color or TYPE_COLORS.note
          )
          label_x = label_x - 110
          if label_index >= 2 then
            break
          end
        end
      end
    else
      local overlay_color = row.color or TYPE_COLORS.note
      parts[#parts + 1] = ('<rect x="%d" y="%d" width="%d" height="%d" rx="8" fill="%s" fill-opacity="0.08" />'):format(
        x + 42,
        text_y - 15,
        width - 54,
        CELL_HEIGHT,
        overlay_color
      )
      parts[#parts + 1] = ('<text x="%d" y="%d" fill="%s" font-size="13" font-family="Iosevka, SFMono-Regular, Menlo, monospace">%s</text>'):format(
        x + 54,
        text_y,
        overlay_color,
        escape_xml(truncate(row.text or "", max_chars))
      )
    end
  end

  parts[#parts + 1] = "</g>"
  return table.concat(parts, "\n")
end

function M.render_svg(snapshot)
  local width = (snapshot.columns * CELL_WIDTH) + (SVG_MARGIN * 2)
  local height = (snapshot.lines * CELL_HEIGHT) + (SVG_MARGIN * 2) + 40
  local parts = {
    ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'):format(
      width,
      height,
      width,
      height
    ),
    ('<rect width="%d" height="%d" fill="%s" />'):format(width, height, SCENE_BG),
    ('<text x="%d" y="%d" fill="%s" font-size="18" font-weight="700" font-family="Avenir Next, ui-sans-serif, sans-serif">%s</text>'):format(
      SVG_MARGIN,
      22,
      TEXT,
      escape_xml(snapshot.name or "Commentry UI Capture")
    ),
    ('<text x="%d" y="%d" fill="%s" font-size="12" font-family="Avenir Next, ui-sans-serif, sans-serif">%s</text>'):format(
      SVG_MARGIN,
      40,
      MUTED,
      escape_xml(snapshot.cwd or "")
    ),
  }

  for _, window in ipairs(snapshot.windows or {}) do
    parts[#parts + 1] = render_window(window)
  end

  parts[#parts + 1] = "</svg>"
  return table.concat(parts, "\n")
end

function M.render_gallery(entries)
  local cards = {}
  for _, entry in ipairs(entries or {}) do
    cards[#cards + 1] = table.concat({
      '<section class="card">',
      ("<h2>%s</h2>"):format(escape_xml(entry.title)),
      ("<p>%s</p>"):format(escape_xml(entry.caption)),
      ('<img src="%s" alt="%s" />'):format(escape_xml(entry.image), escape_xml(entry.title)),
      "</section>",
    }, "\n")
  end

  return table.concat({
    "<!doctype html>",
    "<html>",
    "<head>",
    '<meta charset="utf-8" />',
    "<title>Commentry UI Gallery</title>",
    "<style>",
    "body { background: #f4efe7; color: #2a2118; font-family: 'Avenir Next', ui-sans-serif, sans-serif; margin: 0; padding: 32px; }",
    "h1 { margin: 0 0 8px; font-size: 32px; }",
    "p.lead { margin: 0 0 28px; color: #6d5d4b; max-width: 70ch; }",
    ".grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(420px, 1fr)); gap: 24px; }",
    ".card { background: #fffdfa; border: 1px solid #d8c6ad; border-radius: 20px; padding: 18px; box-shadow: 0 14px 40px rgba(95, 67, 31, 0.08); }",
    ".card h2 { margin: 0 0 6px; font-size: 20px; }",
    ".card p { margin: 0 0 16px; color: #6d5d4b; }",
    ".card img { width: 100%; border-radius: 14px; border: 1px solid #eadcca; background: #fbf7f2; }",
    "</style>",
    "</head>",
    "<body>",
    "<h1>Commentry UI Capture</h1>",
    '<p class="lead">Live Neovim scenarios rendered from a headless Commentry session. Each card is generated from buffer/window/extmark state so an agent can inspect the JSON, while humans can review the PNG gallery.</p>',
    '<div class="grid">',
    table.concat(cards, "\n"),
    "</div>",
    "</body>",
    "</html>",
  }, "\n")
end

local function capture_to_disk(name, out_dir)
  ensure_directory(out_dir)
  local snapshot = M.capture_snapshot(name)
  local json_path = ("%s/%s.json"):format(out_dir, name)
  local svg_path = ("%s/%s.svg"):format(out_dir, name)
  write_file(json_path, vim.json.encode(snapshot))
  write_file(svg_path, M.render_svg(snapshot))
end

local function wait_for(predicate, attempts, delay, cb)
  local ok, value = pcall(predicate)
  if ok and value then
    cb(true, value)
    return
  end
  if attempts <= 0 then
    cb(false, value)
    return
  end
  vim.defer_fn(function()
    wait_for(predicate, attempts - 1, delay, cb)
  end, delay)
end

local function focus_head_diff(done)
  local diffview = require("commentry.diffview")
  wait_for(
    function()
      local view = diffview.get_current_view()
      if not view then
        return false
      end
      local focused = diffview.focus_file_side(view, "head")
      if not focused then
        return false
      end
      local context = diffview.current_file_context()
      if not context then
        return false
      end
      return true
    end,
    20,
    60,
    function(ok)
      if not ok then
        done(false, "target_window_unavailable")
        return
      end
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      done(true)
    end
  )
end

local function count_floats()
  local count = 0
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative ~= nil and cfg.relative ~= "" then
      count = count + 1
    end
  end
  return count
end

local function scenario_popup(out_dir)
  require("commentry.comments")._set_input_provider_for_tests(nil)
  wait_for(
    function()
      local diffview = require("commentry.diffview")
      local view = diffview.get_current_view()
      return view and view.ready
    end,
    30,
    60,
    function(ready)
      if not ready then
        shell_error("diffview never became ready for popup scenario")
        vim.cmd("qa!")
        return
      end
      focus_head_diff(function(ok, err)
        if not ok then
          shell_error(err)
          vim.cmd("qa!")
          return
        end
        local before = count_floats()
        vim.cmd("normal mc")
        wait_for(
          function()
            return count_floats() > before
          end,
          10,
          40,
          function(opened)
            if not opened then
              require("commentry.comments").add_comment()
            end
            vim.defer_fn(function()
              capture_to_disk("comment-popup", out_dir)
              vim.cmd("qa!")
            end, 120)
          end
        )
      end)
    end
  )
end

local function scenario_card(out_dir)
  local comments = require("commentry.comments")
  comments._set_input_provider_for_tests(function(_, cb)
    cb("Consider renaming this variable to reflect that it is the reviewed value, not the baseline.", "suggestion")
  end)
  wait_for(
    function()
      local diffview = require("commentry.diffview")
      local view = diffview.get_current_view()
      return view and view.ready
    end,
    30,
    60,
    function(ready)
      if not ready then
        shell_error("diffview never became ready for card scenario")
        vim.cmd("qa!")
        return
      end
      focus_head_diff(function(ok, err)
        if not ok then
          shell_error(err)
          vim.cmd("qa!")
          return
        end
        comments.add_comment()
        comments._set_input_provider_for_tests(nil)
        vim.defer_fn(function()
          capture_to_disk("comment-card", out_dir)
          vim.cmd("qa!")
        end, 120)
      end)
    end
  )
end

local function scenario_range(out_dir)
  local comments = require("commentry.comments")
  comments._set_input_provider_for_tests(function(_, cb)
    cb(
      "This change spans a few lines, so the range affordance should feel more connected to the edited block.",
      "issue"
    )
  end)
  wait_for(
    function()
      local diffview = require("commentry.diffview")
      local view = diffview.get_current_view()
      return view and view.ready
    end,
    30,
    60,
    function(ready)
      if not ready then
        shell_error("diffview never became ready for range scenario")
        vim.cmd("qa!")
        return
      end
      focus_head_diff(function(ok, err)
        if not ok then
          shell_error(err)
          vim.cmd("qa!")
          return
        end
        local bufnr = vim.api.nvim_get_current_buf()
        vim.fn.setpos("'<", { bufnr, 2, 1, 0 })
        vim.fn.setpos("'>", { bufnr, 4, 1, 0 })
        comments.add_range_comment()
        comments._set_input_provider_for_tests(nil)
        vim.defer_fn(function()
          capture_to_disk("range-comment", out_dir)
          vim.cmd("qa!")
        end, 120)
      end)
    end
  )
end

function M.run()
  vim.cmd("set columns=140 lines=42")
  vim.cmd("Commentry open")

  local scenario = read_env("COMMENTRY_UI_SCENARIO", "popup")
  local out_dir = read_env("COMMENTRY_UI_OUT_DIR", vim.fn.getcwd())

  if scenario == "popup" then
    scenario_popup(out_dir)
    return
  end
  if scenario == "card" then
    scenario_card(out_dir)
    return
  end
  if scenario == "range" then
    scenario_range(out_dir)
    return
  end

  shell_error(("unknown scenario: %s"):format(scenario))
  vim.cmd("qa!")
end

return M
