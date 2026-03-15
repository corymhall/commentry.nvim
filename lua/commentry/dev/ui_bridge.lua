local uv = vim.uv or vim.loop

local M = {}

local CELL_WIDTH = 9
local CELL_HEIGHT = 20
local SVG_MARGIN = 20
local SCENE_BG = "#11161b"
local DEFAULT_BG = "#202830"
local DEFAULT_FG = "#d7dee7"
local FLOAT_SHADOW = "rgba(0,0,0,0.28)"
local TITLE_COLOR = "#8fa7bd"
local FLOAT_BACKDROP = "rgba(7,10,14,0.92)"

---@param value integer|nil
---@return integer, integer, integer
local function hex_to_rgb(value)
  local normalized = type(value) == "number" and value or tonumber(tostring(value):gsub("^#", ""), 16) or 0
  local r = math.floor(normalized / 0x10000) % 0x100
  local g = math.floor(normalized / 0x100) % 0x100
  local b = normalized % 0x100
  return r, g, b
end

---@param color string
---@param fallback string
---@return integer, integer, integer
local function color_components(color, fallback)
  local value = color
  if type(value) ~= "string" or value == "" then
    value = fallback
  end
  if value:sub(1, 1) == "#" then
    return hex_to_rgb(value)
  end
  return hex_to_rgb(fallback)
end

---@param color string
---@param fallback string
---@param alpha number
---@return string
local function rgba(color, fallback, alpha)
  local r, g, b = color_components(color, fallback)
  return ("rgba(%d,%d,%d,%.3f)"):format(r, g, b, alpha)
end

---@param base string
---@param accent string
---@param amount number
---@return string
local function mix_colors(base, accent, amount)
  local base_r, base_g, base_b = color_components(base, DEFAULT_BG)
  local accent_r, accent_g, accent_b = color_components(accent, DEFAULT_FG)
  local t = math.max(0, math.min(1, amount))
  local function mix_channel(a, b)
    return math.floor((a * (1 - t)) + (b * t) + 0.5)
  end
  return ("#%02x%02x%02x"):format(
    mix_channel(base_r, accent_r),
    mix_channel(base_g, accent_g),
    mix_channel(base_b, accent_b)
  )
end

---@param text string
---@return string
local function trim(text)
  return vim.trim(type(text) == "string" and text or "")
end

---@param text string
---@return boolean
local function is_border_text(text)
  return trim(text):match("^[╭╮╰╯│─]+$") ~= nil
end

---@param text string
---@return boolean
local function is_chip_text(text)
  return trim(text):match("^%[[^%]]+%]$") ~= nil
end

---@param value integer|nil
---@param fallback string
---@return string
local function color_to_hex(value, fallback)
  if type(value) ~= "number" or value < 0 then
    return fallback
  end
  return ("#%06x"):format(value)
end

---@param text string
---@return string
local function escape_xml(text)
  return tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;")
end

---@param text string
---@return integer
local function display_width(text)
  return vim.fn.strdisplaywidth(text)
end

---@param path string
local function ensure_directory(path)
  vim.fn.mkdir(path, "p")
end

---@param path string
---@param contents string
local function write_file(path, contents)
  vim.fn.writefile(vim.split(contents, "\n", { plain = true }), path)
end

---@param env table<string, string>|nil
---@return string[]
local function spawn_env(env)
  local merged = vim.fn.environ()
  for key, value in pairs(env or {}) do
    merged[key] = value
  end
  local out = {}
  for key, value in pairs(merged) do
    out[#out + 1] = ("%s=%s"):format(key, value)
  end
  return out
end

---@param width integer
---@param height integer
---@return table
function M.new_screen_state(width, height)
  local state = {
    default_colors = {
      foreground = DEFAULT_FG,
      background = DEFAULT_BG,
      special = DEFAULT_FG,
    },
    highlights = {
      [0] = {},
    },
    grids = {},
    windows = {},
    cursor = {
      grid = 1,
      row = 0,
      col = 0,
    },
    mode = {
      name = "normal",
      index = 0,
      info = {},
    },
    flushes = 0,
  }

  ---@param grid integer
  ---@param grid_width integer
  ---@param grid_height integer
  local function ensure_grid(grid, grid_width, grid_height)
    local existing = state.grids[grid]
    if existing then
      existing.width = grid_width
      existing.height = grid_height
      for row = 1, grid_height do
        existing.rows[row] = existing.rows[row] or {}
      end
      for row = grid_height + 1, #existing.rows do
        existing.rows[row] = nil
      end
      return existing
    end
    local created = {
      width = grid_width,
      height = grid_height,
      rows = {},
    }
    for row = 1, grid_height do
      created.rows[row] = {}
    end
    state.grids[grid] = created
    return created
  end

  ensure_grid(1, width, height)

  ---@param grid integer
  ---@return table
  local function grid_info(grid)
    return state.grids[grid] or ensure_grid(grid, 1, 1)
  end

  ---@param grid integer
  ---@param row integer
  ---@return table
  local function row_info(grid, row)
    local info = grid_info(grid)
    info.rows[row + 1] = info.rows[row + 1] or {}
    return info.rows[row + 1]
  end

  ---@param grid integer
  local function clear_grid(grid)
    local info = grid_info(grid)
    info.rows = {}
    for row = 1, info.height do
      info.rows[row] = {}
    end
  end

  ---@param grid integer
  ---@param row integer
  ---@param col integer
  ---@param text string
  ---@param hl_id integer
  local function set_cell(grid, row, col, text, hl_id)
    local cells = row_info(grid, row)
    cells[col + 1] = {
      text = text,
      hl_id = hl_id or 0,
    }
  end

  ---@param window table
  ---@return integer, integer
  local function resolve_window_position(window)
    if window.kind == "float" then
      local anchor_window = state.windows[window.anchor_grid]
      local anchor_row = window.anchor_row or 0
      local anchor_col = window.anchor_col or 0
      local base_row = 0
      local base_col = 0
      if anchor_window then
        local parent_row, parent_col = resolve_window_position(anchor_window)
        base_row = parent_row
        base_col = parent_col
      end
      local row = base_row + anchor_row
      local col = base_col + anchor_col
      local grid = state.grids[window.grid]
      local width_cells = grid and grid.width or window.width or 0
      local height_cells = grid and grid.height or window.height or 0
      local anchor = window.anchor or "NW"
      if anchor:find("S", 1, true) then
        row = row - height_cells + 1
      end
      if anchor:find("E", 1, true) then
        col = col - width_cells + 1
      end
      return row, col
    end
    return window.row or 0, window.col or 0
  end

  ---@param event string
  ---@param args table
  function state:apply(event, args)
    if event == "default_colors_set" then
      self.default_colors = {
        foreground = color_to_hex(args[1], DEFAULT_FG),
        background = color_to_hex(args[2], DEFAULT_BG),
        special = color_to_hex(args[3], DEFAULT_FG),
      }
      return
    end

    if event == "hl_attr_define" then
      self.highlights[args[1]] = args[2] or {}
      return
    end

    if event == "grid_resize" then
      ensure_grid(args[1], args[2], args[3])
      return
    end

    if event == "grid_clear" then
      clear_grid(args[1])
      return
    end

    if event == "grid_destroy" then
      self.grids[args[1]] = nil
      self.windows[args[1]] = nil
      return
    end

    if event == "grid_line" then
      local grid = args[1]
      local row = args[2]
      local col_start = args[3]
      local cells = args[4] or {}
      local current_hl = 0
      local col = col_start
      for _, cell in ipairs(cells) do
        local text = cell[1] or " "
        local hl_id = cell[2]
        if hl_id ~= nil then
          current_hl = hl_id
        end
        local repeat_count = cell[3] or 1
        for _ = 1, repeat_count do
          set_cell(grid, row, col, text, current_hl)
          col = col + 1
        end
      end
      return
    end

    if event == "grid_cursor_goto" then
      self.cursor = {
        grid = args[1],
        row = args[2],
        col = args[3],
      }
      return
    end

    if event == "mode_info_set" then
      self.mode.info = args[2] or {}
      return
    end

    if event == "mode_change" then
      self.mode.name = args[1] or self.mode.name
      self.mode.index = args[2] or self.mode.index
      return
    end

    if event == "win_pos" then
      self.windows[args[1]] = {
        grid = args[1],
        win = args[2],
        row = args[3],
        col = args[4],
        width = args[5],
        height = args[6],
        kind = "normal",
        zindex = 10,
      }
      return
    end

    if event == "win_float_pos" then
      local existing = self.windows[args[1]] or { grid = args[1], win = args[2] }
      existing.kind = "float"
      existing.anchor = args[3]
      existing.anchor_grid = args[4]
      existing.anchor_row = args[5]
      existing.anchor_col = args[6]
      existing.mouse_enabled = args[7]
      existing.zindex = args[8] or 50
      self.windows[args[1]] = existing
      return
    end

    if event == "msg_set_pos" then
      self.windows[args[1]] = {
        grid = args[1],
        win = args[1],
        row = args[2],
        col = 0,
        kind = "message",
        zindex = 200,
      }
      return
    end

    if event == "win_hide" or event == "win_close" then
      local window = self.windows[args[1]]
      if window then
        window.hidden = true
      end
      return
    end

    if event == "flush" then
      self.flushes = self.flushes + 1
      return
    end
  end

  function state:apply_batch(batch)
    for _, item in ipairs(batch or {}) do
      local event = item[1]
      for index = 2, #item do
        self:apply(event, item[index])
      end
    end
  end

  ---@param hl_id integer
  ---@return table
  function state:highlight(hl_id)
    local attr = self.highlights[hl_id] or {}
    local fg = color_to_hex(attr.foreground, self.default_colors.foreground)
    local bg = color_to_hex(attr.background, self.default_colors.background)
    if attr.reverse then
      fg, bg = bg, fg
    end
    return {
      fg = fg,
      bg = bg,
      bold = attr.bold == true,
      italic = attr.italic == true,
      blend = math.max(0, math.min(100, tonumber(attr.blend) or 0)),
    }
  end

  ---@return table
  function state:cursor_style()
    local index = (tonumber(self.mode.index) or 0) + 1
    local mode_info = self.mode.info[index] or {}
    return {
      mode = self.mode.name,
      shape = mode_info.cursor_shape or "block",
      cell_percentage = tonumber(mode_info.cell_percentage) or 100,
      blinkwait = tonumber(mode_info.blinkwait) or 0,
      hl_id = tonumber(mode_info.attr_id),
    }
  end

  ---@param grid integer
  ---@return table[]
  function state:grid_rows(grid)
    local info = grid_info(grid)
    local rows = {}
    for row = 0, info.height - 1 do
      local cells = info.rows[row + 1] or {}
      local segments = {}
      local text = ""
      local hl_id = 0
      local width_acc = 0
      local function flush()
        if text == "" then
          return
        end
        segments[#segments + 1] = {
          text = text,
          hl_id = hl_id,
          width = width_acc,
        }
        text = ""
        width_acc = 0
      end

      for col = 0, info.width - 1 do
        local cell = cells[col + 1] or { text = " ", hl_id = 0 }
        local cell_text = cell.text
        if cell_text == "" then
          cell_text = " "
        end
        local cell_hl = cell.hl_id or 0
        if text ~= "" and cell_hl ~= hl_id then
          flush()
        end
        if text == "" then
          hl_id = cell_hl
        end
        text = text .. cell_text
        width_acc = width_acc + display_width(cell_text)
      end
      flush()
      rows[#rows + 1] = segments
    end
    return rows
  end

  ---@param name string
  ---@return table
  function state:snapshot(name)
    local windows = {}

    local root = grid_info(1)
    windows[#windows + 1] = {
      grid = 1,
      win = 0,
      kind = "editor",
      row = 0,
      col = 0,
      width = root.width,
      height = root.height,
      zindex = 0,
      rows = self:grid_rows(1),
    }

    for grid, window in pairs(self.windows) do
      if not window.hidden then
        local info = self.grids[grid]
        if info then
          local row, col = resolve_window_position(window)
          windows[#windows + 1] = {
            grid = grid,
            win = window.win,
            kind = window.kind,
            row = row,
            col = col,
            width = info.width,
            height = info.height,
            zindex = window.zindex or 10,
            rows = self:grid_rows(grid),
          }
        end
      end
    end

    table.sort(windows, function(a, b)
      if a.zindex ~= b.zindex then
        return a.zindex < b.zindex
      end
      if a.row ~= b.row then
        return a.row < b.row
      end
      return a.col < b.col
    end)

    return {
      name = name,
      columns = root.width,
      lines = root.height,
      default_colors = self.default_colors,
      cursor = vim.deepcopy(self.cursor),
      cursor_style = self:cursor_style(),
      windows = windows,
    }
  end

  return state
end

---@param snapshot table
---@return string
function M.render_svg(snapshot)
  local width = (snapshot.columns * CELL_WIDTH) + (SVG_MARGIN * 2)
  local height = (snapshot.lines * CELL_HEIGHT) + (SVG_MARGIN * 2)
  local parts = {
    ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'):format(
      width,
      height,
      width,
      height
    ),
    ('<rect width="%d" height="%d" fill="%s" />'):format(width, height, SCENE_BG),
  }

  local cursor_window = nil
  for _, window in ipairs(snapshot.windows or {}) do
    if window.grid == snapshot.cursor.grid then
      cursor_window = window
      break
    end
  end

  for _, window in ipairs(snapshot.windows or {}) do
    local x = SVG_MARGIN + (window.col * CELL_WIDTH)
    local y = SVG_MARGIN + (window.row * CELL_HEIGHT)
    local window_width = window.width * CELL_WIDTH
    local window_height = window.height * CELL_HEIGHT

    if window.kind == "float" then
      parts[#parts + 1] = ('<rect x="%d" y="%d" width="%d" height="%d" rx="10" fill="%s" />'):format(
        x + 6,
        y + 8,
        window_width,
        window_height,
        FLOAT_SHADOW
      )
      parts[#parts + 1] = ('<rect x="%d" y="%d" width="%d" height="%d" rx="%d" fill="%s" />'):format(
        x,
        y,
        window_width,
        window_height,
        10,
        FLOAT_BACKDROP
      )
    end

    for row_index, segments in ipairs(window.rows or {}) do
      local row_y = y + ((row_index - 1) * CELL_HEIGHT)
      local cursor_on_row = cursor_window == window and snapshot.cursor.row == (row_index - 1)
      if cursor_on_row then
        local cursor_x = x + (snapshot.cursor.col * CELL_WIDTH)
        local style = snapshot.cursor_style or {}
        local shape = style.shape or "block"
        local cell_percentage = math.max(1, math.min(100, tonumber(style.cell_percentage) or 100))
        local cursor_highlight = nil
        if snapshot.highlight_resolver and type(style.hl_id) == "number" then
          cursor_highlight = snapshot.highlight_resolver(style.hl_id)
        end
        local cursor_fill = TITLE_COLOR
        if cursor_highlight then
          if shape == "block" then
            cursor_fill = cursor_highlight.bg ~= snapshot.default_colors.background and cursor_highlight.bg
              or cursor_highlight.fg
          else
            cursor_fill = cursor_highlight.fg
          end
        end

        if shape == "vertical" then
          local cursor_width = math.max(2, math.floor((CELL_WIDTH * cell_percentage) / 100))
          parts[#parts + 1] = ('<rect x="%d" y="%d" width="%d" height="%d" rx="1" fill="%s" />'):format(
            cursor_x,
            row_y + 2,
            cursor_width,
            CELL_HEIGHT - 4,
            cursor_fill
          )
        elseif shape == "horizontal" then
          local cursor_height = math.max(2, math.floor((CELL_HEIGHT * cell_percentage) / 100))
          parts[#parts + 1] = ('<rect x="%d" y="%d" width="%d" height="%d" rx="1" fill="%s" />'):format(
            cursor_x,
            row_y + CELL_HEIGHT - cursor_height,
            CELL_WIDTH,
            cursor_height,
            cursor_fill
          )
        else
          parts[#parts + 1] = ('<rect x="%d" y="%d" width="%d" height="%d" rx="2" fill="%s" fill-opacity="0.40" />'):format(
            cursor_x,
            row_y + 2,
            CELL_WIDTH,
            CELL_HEIGHT - 4,
            cursor_fill
          )
        end
      end

      local col_x = x
      for _, segment in ipairs(segments) do
        local highlight = snapshot.highlight_resolver and snapshot.highlight_resolver(segment.hl_id) or nil
        local fg = highlight and highlight.fg or snapshot.default_colors.foreground
        local bg = highlight and highlight.bg or snapshot.default_colors.background
        local bg_opacity = highlight and (1 - (highlight.blend / 100)) or 1
        local font_weight = highlight and highlight.bold and "700" or "400"
        local font_style = highlight and highlight.italic and "italic" or "normal"
        parts[#parts + 1] = ('<rect x="%d" y="%d" width="%d" height="%d" fill="%s" fill-opacity="%.3f" />'):format(
          col_x,
          row_y,
          segment.width * CELL_WIDTH,
          CELL_HEIGHT,
          bg,
          bg_opacity
        )

        local trimmed = trim(segment.text)
        local float_chrome = window.kind == "float"
          and (row_index == 1 or row_index == #window.rows)
          and trimmed ~= ""
          and not is_border_text(segment.text)
        if float_chrome then
          parts[#parts + 1] = ('<rect x="%d" y="%d" width="%d" height="%d" rx="8" fill="%s" stroke="%s" stroke-width="1" />'):format(
            col_x + 3,
            row_y + 2,
            math.max(8, (segment.width * CELL_WIDTH) - 6),
            CELL_HEIGHT - 4,
            mix_colors(bg, fg, 0.12),
            rgba(fg, DEFAULT_FG, 0.35)
          )
          font_weight = "700"
        elseif is_chip_text(segment.text) then
          parts[#parts + 1] = ('<rect x="%d" y="%d" width="%d" height="%d" rx="8" fill="%s" stroke="%s" stroke-width="1" />'):format(
            col_x + 2,
            row_y + 3,
            math.max(12, (segment.width * CELL_WIDTH) - 4),
            CELL_HEIGHT - 6,
            mix_colors(bg, fg, 0.10),
            rgba(fg, DEFAULT_FG, 0.25)
          )
          font_weight = "700"
        end

        parts[#parts + 1] = ('<text x="%d" y="%d" fill="%s" font-size="13" font-family="Iosevka, SFMono-Regular, Menlo, monospace" font-weight="%s" font-style="%s">%s</text>'):format(
          col_x,
          row_y + 15,
          fg,
          font_weight,
          font_style,
          escape_xml(segment.text)
        )
        col_x = col_x + (segment.width * CELL_WIDTH)
      end
    end
  end

  parts[#parts + 1] = "</svg>"
  return table.concat(parts, "\n")
end

---@class commentry.dev.UiBridge
---@field stdin uv_pipe_t
---@field stdout uv_pipe_t
---@field stderr uv_pipe_t
---@field handle uv_process_t
---@field pid integer
---@field unpacker any
---@field buffer string
---@field screen table
---@field pending table<integer, table>
---@field next_id integer
---@field stderr_chunks string[]
---@field exited boolean
local Bridge = {}
Bridge.__index = Bridge

---@param opts table
---@return commentry.dev.UiBridge
function Bridge.new(opts)
  local self = setmetatable({
    stdin = assert(uv.new_pipe(false)),
    stdout = assert(uv.new_pipe(false)),
    stderr = assert(uv.new_pipe(false)),
    unpacker = vim.mpack.Unpacker(),
    buffer = "",
    pending = {},
    next_id = 1,
    stderr_chunks = {},
    exited = false,
    screen = M.new_screen_state(opts.width, opts.height),
  }, Bridge)

  local spawn_opts = {
    args = opts.args,
    cwd = opts.cwd,
    env = spawn_env(opts.env),
    stdio = { self.stdin, self.stdout, self.stderr },
  }

  self.handle, self.pid = assert(uv.spawn(opts.cmd, spawn_opts, function()
    self.exited = true
  end))

  self.stdout:read_start(function(err, data)
    assert(not err, err)
    if not data then
      return
    end
    self:handle_stdout(data)
  end)

  self.stderr:read_start(function(err, data)
    assert(not err, err)
    if not data then
      return
    end
    self.stderr_chunks[#self.stderr_chunks + 1] = data
  end)

  return self
end

---@param obj any
function Bridge:write(obj)
  self.stdin:write(vim.mpack.encode(obj))
end

---@param method string
---@param params any[]
function Bridge:notify(method, params)
  self:write({ 2, method, params or {} })
end

---@param method string
---@param params any[]
---@param timeout integer|nil
---@return any, any
function Bridge:request(method, params, timeout)
  local id = self.next_id
  self.next_id = self.next_id + 1
  self.pending[id] = { done = false }
  self:write({ 0, id, method, params or {} })

  local ok = vim.wait(timeout or 5000, function()
    return self.pending[id].done or self.exited
  end, 10)

  local pending = self.pending[id]
  self.pending[id] = nil
  if not ok or not pending or not pending.done then
    error(("RPC timeout calling %s\nstderr:\n%s"):format(method, table.concat(self.stderr_chunks)))
  end
  if pending.error ~= vim.NIL and pending.error ~= nil then
    error(("RPC error calling %s: %s"):format(method, vim.inspect(pending.error)))
  end
  return pending.result, pending.error
end

---@param data string
function Bridge:handle_stdout(data)
  self.buffer = self.buffer .. data
  local pos = 1
  while pos <= #self.buffer do
    local msg, nextpos = self.unpacker(self.buffer, pos)
    if msg == nil then
      break
    end
    pos = nextpos
    self:handle_message(msg)
  end
  if pos > 1 then
    self.buffer = self.buffer:sub(pos)
  end
end

---@param msg any[]
function Bridge:handle_message(msg)
  local kind = msg[1]
  if kind == 1 then
    local id = msg[2]
    if self.pending[id] then
      self.pending[id].done = true
      self.pending[id].error = msg[3]
      self.pending[id].result = msg[4]
    end
    return
  end

  if kind == 2 and msg[2] == "redraw" then
    self.screen:apply_batch(msg[3])
    return
  end
end

---@param timeout integer
function Bridge:wait_for_flush(timeout)
  local target = self.screen.flushes + 1
  local ok = vim.wait(timeout, function()
    return self.screen.flushes >= target
  end, 10)
  if not ok then
    error(("Timed out waiting for redraw flush\nstderr:\n%s"):format(table.concat(self.stderr_chunks)))
  end
end

---@param timeout integer
---@param predicate fun():boolean
function Bridge:wait_until(timeout, predicate)
  local ok = vim.wait(timeout, predicate, 20)
  if not ok then
    error(("Timed out waiting for state\nstderr:\n%s"):format(table.concat(self.stderr_chunks)))
  end
end

function Bridge:close()
  pcall(function()
    self:request("nvim_command", { "qa!" }, 2000)
  end)
  if self.handle and not self.exited then
    pcall(self.handle.kill, self.handle, "sigterm")
  end
  pcall(self.stdin.close, self.stdin)
  pcall(self.stdout.close, self.stdout)
  pcall(self.stderr.close, self.stderr)
  if self.handle then
    pcall(self.handle.close, self.handle)
  end
end

M.Bridge = Bridge

---@param snapshot table
---@param screen table
function M.write_snapshot_files(snapshot, screen, out_dir, name)
  ensure_directory(out_dir)
  local render_snapshot = vim.deepcopy(snapshot)
  render_snapshot.highlight_resolver = function(hl_id)
    return screen:highlight(hl_id)
  end
  write_file(("%s/%s.json"):format(out_dir, name), vim.json.encode(snapshot))
  write_file(("%s/%s.svg"):format(out_dir, name), M.render_svg(render_snapshot))
end

return M
