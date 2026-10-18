local Render = require("commentry.inbox.render")
local Source = require("commentry.inbox.source")
local Store = require("commentry.inbox.store")
local Util = require("commentry.util")
local M = {}
local active
local refresh

local function close_view(view)
  view.closed = true
  if active == view then
    if view.group then
      vim.api.nvim_del_augroup_by_id(view.group)
    end
    active = nil
  end
  if vim.api.nvim_tabpage_is_valid(view.tab) then
    -- Native window commands may close one panel or leave this as the last tab.
    -- Dispose of the whole owned view so reopening never reuses wiped buffers.
    if #vim.api.nvim_list_tabpages() == 1 then
      vim.cmd.tabnew()
    end
    vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(view.tab))
  end
end

local function stamp()
  return Store.revision() or "unavailable"
end

local function report(value, err)
  if not value then
    Util.error(err or "Inbox operation failed")
  end
  return value
end

local write = Render.write

local function inspect(thread)
  local rows = {
    "Thread details",
    "",
    "ID       " .. thread.id,
    "Project  " .. thread.project,
    "Created  " .. thread.created_at,
    "Source   " .. (thread.source.path or thread.source.origin or "Copied text"),
  }
  if thread.source.git then
    vim.list_extend(rows, {
      "Branch   " .. (thread.source.git.branch or "detached"),
      "HEAD     " .. (thread.source.git.head or "unborn"),
      "Blob     " .. (thread.source.git.blob or "uncommitted file"),
      "Buffer   " .. (thread.source.modified and "Unsaved changes captured" or "Saved file captured"),
    })
  end
  return rows
end

local function details(rows)
  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.max(1, math.min(88, vim.o.columns - 6))
  local height = math.max(1, math.min(#rows, vim.o.lines - 6))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    border = "rounded",
    style = "minimal",
    title = " Commentry ",
    footer = " q close ",
  })
  vim.bo[buf].bufhidden = "wipe"
  vim.wo[win].wrap = true
  write(buf, rows, "text")
  Render.mark(buf, 0, "Title")
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, desc = "Close inbox details" })
  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, desc = "Close inbox details" })
end

-- A real buffer keeps multiline editing and save/cancel behavior predictable.
local function compose(title, initial, save, dispatch)
  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.max(1, math.min(76, vim.o.columns - 6))
  local height = math.max(1, math.min(10, vim.o.lines - 6))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    border = "rounded",
    title = " " .. Render.clip(title, width - 4) .. " ",
    footer = dispatch and " Ctrl-s save / Ctrl-d save + send / q cancel " or " Ctrl-s save / q cancel ",
    style = "minimal",
  })
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  vim.wo[win].wrap = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial or { "" })
  local function submit(send)
    local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    if not body:find("%S") then
      Util.warn("Write a comment before saving")
      return
    end
    local result = save(body)
    if result then
      vim.cmd.stopinsert()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if send and dispatch then
        dispatch(result)
      end
    end
  end
  vim.keymap.set({ "n", "i" }, "<C-s>", function()
    submit(false)
  end, { buffer = buf, desc = "Save inbox message" })
  if dispatch then
    vim.keymap.set({ "n", "i" }, "<C-d>", function()
      submit(true)
    end, { buffer = buf, desc = "Save and send inbox message" })
  end
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, desc = "Cancel inbox message" })
  vim.cmd.startinsert()
end

local function send_thread(id, mode)
  local result, err = require("commentry.inbox.agent").send(id, mode)
  if not report(result, err) then
    return
  end
  Util.info(
    mode == "queue" and "Added to the Commentry queue" or "Delegated thread to Sidekick; delivery is not confirmed"
  )
  if active and vim.api.nvim_tabpage_is_valid(active.tab) then
    refresh(active)
  end
end

function M.new_thread()
  local view = active and vim.api.nvim_get_current_tabpage() == active.tab and active or nil
  local project = view and view.project or Source.project()
  compose("New project thread", nil, function(body)
    local id, err =
      Store.create({ project = project, body = body, source = { kind = "text", lines = {}, origin = "general" } })
    if not report(id, err) then
      return false
    end
    if view then
      view.filter = "all"
      refresh(view, id)
    end
    return id
  end, function(id)
    send_thread(id, view and view.delivery_mode or "queue")
  end)
end

function M.comment(args)
  args = args or {}
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local first = args.range and args.range > 0 and args.line1 or row
  local last = args.range and args.range > 0 and args.line2 or row
  local capture, err = Source.capture(vim.api.nvim_get_current_buf(), first, last)
  if not report(capture, err) then
    return
  end
  compose("Comment on " .. capture.source.path .. ":" .. first .. "-" .. last, nil, function(body)
    capture.body = body
    local id, create_err = Store.create(capture)
    if not report(id, create_err) then
      return false
    end
    Util.info("Saved inbox thread " .. id)
    return true
  end)
end

function M.capture_text(register)
  register = register == "" and '"' or register or '"'
  if #register ~= 1 then
    Util.error("capture-text accepts a single register name")
    return
  end
  local contents = vim.fn.getreg(register, 1, true)
  if #contents == 0 or not table.concat(contents, "\n"):find("%S") then
    Util.warn("Capture register is empty")
    return
  end
  local capture = {
    project = Source.project(),
    source = { kind = "text", lines = contents, origin = "register:" .. register },
  }
  compose("Comment on captured text", nil, function(body)
    capture.body = body
    local id, err = Store.create(capture)
    if not report(id, err) then
      return false
    end
    Util.info("Saved inbox thread " .. id)
    return true
  end)
end

local function selected(view)
  if not vim.api.nvim_win_is_valid(view.list_win) then
    return nil
  end
  return view.threads[vim.api.nvim_win_get_cursor(view.list_win)[1]]
end

local function render_detail(view)
  if view.closed then
    return
  end
  local thread = selected(view)
  if not thread then
    write(view.source_buf, { "No threads in this scope.", "", ":Commentry comment", ":Commentry capture-text" }, "text")
    write(view.thread_buf, { "Capture code or text to start a conversation." }, "markdown")
    return
  end
  Render.selection(view, vim.api.nvim_win_get_cursor(view.list_win)[1])
  local comparison, err = Source.compare(thread, view.mode, view.context)
  if not comparison then
    comparison = { lines = { err }, label = "Comparison unavailable", filetype = "text" }
  end
  Render.source(view, thread, comparison)
  Render.conversation(view, thread)
end

refresh = function(view, select_id)
  if view.closed or not vim.api.nvim_tabpage_is_valid(view.tab) then
    return
  end
  local old = selected(view)
  local scroll = {}
  for _, win in ipairs({ view.source_win, view.thread_win }) do
    if vim.api.nvim_win_is_valid(win) then
      scroll[win] = vim.api.nvim_win_call(win, vim.fn.winsaveview)
    end
  end
  -- Record the revision before reading. A reply committed during the read must
  -- still differ from this stamp so the next poll cannot silently skip it.
  local revision = stamp()
  local threads, err = Store.list(view.project)
  if not report(threads, err) then
    return
  end
  view.threads, view.outdated = threads, {}
  view.threads = vim.tbl_filter(function(thread)
    if view.filter == "unread" then
      return thread.unread or view.pin_id == thread.id
    end
    if view.filter == "read" then
      return not thread.unread
    end
    if view.filter == "open" then
      return not thread.resolved
    end
    if view.filter == "resolved" then
      return thread.resolved
    end
    if view.filter == "queued" then
      for _, item in ipairs(thread.queue) do
        if item.status == "pending" or item.status == "claimed" then
          return true
        end
      end
      return false
    end
    return true
  end, threads)
  local row = 1
  for index, thread in ipairs(view.threads) do
    local comparison = Source.compare(thread, "since")
    view.outdated[thread.id] = comparison and comparison.outdated == true
    if thread.id == (select_id or (old and old.id)) then
      row = index
    end
  end
  Render.list(view)
  vim.api.nvim_win_set_cursor(view.list_win, { row, 0 })
  render_detail(view)
  if old and selected(view) and selected(view).id == old.id then
    for win, saved in pairs(scroll) do
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_call(win, function()
          vim.fn.winrestview(saved)
        end)
      end
    end
  end
  local scope_label = view.project and vim.fs.basename(view.project) or "All projects"
  vim.wo[view.list_win].winbar = " " .. scope_label:gsub("%%", "%%%%") .. " / " .. view.filter .. " / " .. #view.threads
  vim.wo[view.thread_win].winbar = " Conversation %=%#CommentryInboxMuted#" .. view.delivery_mode .. "  s send "
  view.stamp = revision
end

local function scratch(name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  return buf
end

local function window(buf)
  vim.api.nvim_win_set_buf(0, buf)
  vim.wo.number, vim.wo.relativenumber = false, false
  vim.wo.signcolumn = "no"
  vim.wo.wrap = true
  vim.wo.linebreak = true
  vim.wo.breakindent = true
  vim.wo.cursorline = false
  vim.wo.fillchars = "eob: "
  vim.wo.statusline = "%#CommentryInboxMuted#%=%l / %L "
  return vim.api.nvim_get_current_win()
end

local function layout(view)
  if view.closed then
    return
  end
  local wide = vim.o.columns >= 140
  if view.wide == wide then
    return
  end
  view.reflowing = true
  local focus = vim.api.nvim_get_current_win()
  local target = focus == view.thread_win and "thread_win" or focus == view.source_win and "source_win" or "list_win"
  for _, buf in ipairs({ view.source_buf, view.thread_buf }) do
    vim.bo[buf].bufhidden = "hide"
  end
  for _, win in ipairs({ view.source_win or -1, view.thread_win or -1 }) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.api.nvim_set_current_win(view.list_win)
  vim.cmd("rightbelow vsplit")
  view.source_win = window(view.source_buf)
  vim.cmd(wide and "rightbelow vsplit" or "rightbelow split")
  view.thread_win = window(view.thread_buf)
  for _, buf in ipairs({ view.source_buf, view.thread_buf }) do
    vim.bo[buf].bufhidden = "wipe"
  end
  vim.wo[view.source_win].winbar = " Source %=%#CommentryInboxMuted#c compare  e context "
  vim.wo[view.thread_win].winbar = " Conversation %=%#CommentryInboxMuted#r reply  ? help "
  vim.api.nvim_win_set_width(view.list_win, math.min(40, math.floor(vim.o.columns / 4)))
  if wide then
    vim.api.nvim_win_set_width(
      view.thread_win,
      math.floor((vim.o.columns - vim.api.nvim_win_get_width(view.list_win)) * 0.48)
    )
  end
  view.wide = wide
  vim.api.nvim_set_current_win(view[target])
  view.reflowing = false
end

function M.open(scope)
  Render.highlights()
  if active and active.closed then
    close_view(active)
  end
  local project = Source.project()
  if scope == "all" then
    project = nil
  end
  if active and vim.api.nvim_tabpage_is_valid(active.tab) then
    vim.api.nvim_set_current_tabpage(active.tab)
    active.project = project
    active.filter = scope and scope ~= "" and scope ~= "all" and scope or "all"
    active.pin_id = nil
    layout(active)
    vim.wo[active.list_win].winbar = " Inbox / "
      .. (project and vim.fs.basename(project):gsub("%%", "%%%%") or "All projects")
    refresh(active)
    return active
  end
  vim.cmd.tabnew()
  local view = {
    tab = vim.api.nvim_get_current_tabpage(),
    project = project,
    mode = "since",
    context = 4,
    filter = scope and scope ~= "" and scope ~= "all" and scope or "all",
    delivery_mode = "queue",
    threads = {},
    outdated = {},
    list_buf = scratch("commentry://inbox"),
    source_buf = scratch("commentry://source"),
    thread_buf = scratch("commentry://thread"),
  }
  active = view
  view.list_win = window(view.list_buf)
  layout(view)
  vim.wo[view.list_win].winbar = " Inbox / "
    .. (project and vim.fs.basename(project):gsub("%%", "%%%%") or "All projects")
  vim.wo[view.source_win].winbar = " Source %=%#CommentryInboxMuted#c compare  e context "
  vim.wo[view.thread_win].winbar = " Conversation %=%#CommentryInboxMuted#r reply  ? help "
  vim.wo[view.list_win].wrap = false
  vim.wo[view.list_win].scrolloff = 2
  vim.api.nvim_win_set_width(view.list_win, math.min(40, math.floor(vim.o.columns / 4)))
  if vim.o.columns >= 140 then
    vim.api.nvim_win_set_width(
      view.thread_win,
      math.floor((vim.o.columns - vim.api.nvim_win_get_width(view.list_win)) * 0.48)
    )
  end
  vim.api.nvim_set_current_win(view.list_win)
  local function close()
    close_view(view)
  end
  local function update(input)
    local thread = selected(view)
    if thread then
      local event, err = Store.update(thread.id, input)
      if report(event, err) then
        refresh(view)
      end
    end
  end
  local function reply()
    local thread = selected(view)
    if thread then
      local id = thread.id
      compose("Reply", nil, function(body)
        local event, err = Store.update(id, { kind = "reply", body = body })
        if not report(event, err) then
          return false
        end
        refresh(view)
        return id
      end, function(reply_id)
        send_thread(reply_id, view.delivery_mode)
      end)
    end
  end
  local function comparison()
    vim.ui.select({ "since", "original", "agent" }, { prompt = "Comparison" }, function(mode)
      if mode and vim.api.nvim_tabpage_is_valid(view.tab) then
        view.mode = mode
        render_detail(view)
      end
    end)
  end
  local function toggle()
    local thread = selected(view)
    if thread then
      update({ kind = "resolve", resolved = not thread.resolved })
    end
  end
  local function mark_read(read)
    if view.reflowing or view.closed then
      return
    end
    local thread = selected(view)
    if not thread then
      return
    end
    if read and not thread.unread then
      return
    end
    local event, err = Store.update(thread.id, { kind = "read", read = read, seen = thread.incoming })
    if report(event, err) then
      thread.unread = not read
      if read and view.filter == "unread" then
        view.pin_id = thread.id
      end
      Render.list(view)
      render_detail(view)
    end
  end
  local function enter()
    vim.api.nvim_set_current_win(view.thread_win)
    mark_read(true)
  end
  for _, buf in ipairs({ view.list_buf, view.source_buf, view.thread_buf }) do
    for key, mapping in pairs({
      q = { close, "Close inbox" },
      R = {
        function()
          view.pin_id = nil
          refresh(view)
        end,
        "Refresh inbox",
      },
      r = { reply, "Reply to thread" },
      n = { M.new_thread, "New standalone thread" },
      ["<CR>"] = { enter, "Open conversation and mark read" },
      u = {
        function()
          local thread = selected(view)
          if thread then
            mark_read(thread.unread)
          end
        end,
        "Toggle read or unread",
      },
      f = {
        function()
          vim.ui.select(
            { "all", "unread", "read", "open", "resolved", "queued" },
            { prompt = "Inbox filter" },
            function(filter)
              if filter and vim.api.nvim_tabpage_is_valid(view.tab) then
                view.pin_id = nil
                view.filter = filter
                refresh(view)
              end
            end
          )
        end,
        "Filter inbox",
      },
      m = {
        function()
          vim.ui.select({ "queue", "steer" }, { prompt = "Send mode" }, function(mode)
            if mode and vim.api.nvim_tabpage_is_valid(view.tab) then
              view.delivery_mode = mode
              refresh(view)
            end
          end)
        end,
        "Choose send mode",
      },
      s = {
        function()
          local thread = selected(view)
          if thread then
            send_thread(thread.id, view.delivery_mode)
          end
        end,
        "Queue or send selected thread",
      },
      S = {
        function()
          local result, err = require("commentry.inbox.agent").worker(view.project)
          if report(result, err) then
            Util.info("Delegated queue worker instructions to Sidekick")
          end
        end,
        "Ask Sidekick to process the project queue",
      },
      d = {
        function()
          local thread = selected(view)
          if not thread then
            return
          end
          for _, item in ipairs(thread.queue) do
            if item.status == "pending" then
              update({ kind = "cancel", queue_id = item.id, pending_only = true })
              return
            end
          end
          Util.info("No pending request to remove; claimed work must finish or be explicitly cancelled through the CLI")
        end,
        "Remove the oldest pending request from the queue",
      },
      x = { toggle, "Resolve or reopen thread" },
      c = { comparison, "Choose comparison" },
      e = {
        function()
          view.context = view.context == 4 and 16 or 4
          render_detail(view)
        end,
        "Expand or collapse source context",
      },
      i = {
        function()
          local thread = selected(view)
          if thread then
            details(inspect(thread))
          end
        end,
        "Inspect thread and Git provenance",
      },
      ["?"] = {
        function()
          details({
            "Inbox keys",
            "",
            "j / k   Select a thread in the list",
            "r       Reply",
            "n       New standalone project thread",
            "Enter   Open and mark read",
            "u       Toggle read/unread",
            "f       Filter threads",
            "m       Choose queue or steer mode",
            "s       Queue or send the selected thread",
            "S       Ask Sidekick to process the queue",
            "d       Remove the oldest pending queue request",
            "Ctrl-d  Save and send from the composer",
            "Ctrl-h/j/k/l  Move between panels",
            "x       Resolve or reopen",
            "c       Choose comparison",
            "e       Expand or collapse code context",
            "i       Inspect capture and Git details",
            "R       Refresh",
            "q       Close inbox",
          })
        end,
        "Show inbox help",
      },
    }) do
      vim.keymap.set("n", key, mapping[1], { buffer = buf, desc = mapping[2] })
    end
    for key, direction in pairs({ h = "h", j = "j", k = "k", l = "l" }) do
      vim.keymap.set("n", "<C-" .. key .. ">", function()
        vim.cmd("wincmd " .. direction)
      end, { buffer = buf, desc = "Move to the " .. direction .. " panel" })
    end
  end
  local group = vim.api.nvim_create_augroup("CommentryInbox", { clear = true })
  view.group = group
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    desc = "Dispose of the inbox when a native command closes an owned panel",
    callback = function(args)
      local win = tonumber(args.match)
      if view.reflowing or view.closed then
        return
      end
      if win == view.list_win or win == view.source_win or win == view.thread_win then
        view.closed = true
        -- WinClosed runs while Neovim is changing the window tree.
        vim.schedule(function()
          close_view(view)
        end)
      end
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = view.list_buf,
    desc = "Update the selected inbox conversation and diff",
    callback = function()
      render_detail(view)
    end,
  })
  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    desc = "Refresh external inbox replies when Neovim regains focus",
    callback = function()
      if vim.api.nvim_get_current_tabpage() == view.tab then
        refresh(view)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    buffer = view.thread_buf,
    desc = "Mark the displayed conversation read when opening its panel",
    callback = function()
      if view.reflowing then
        return
      end
      mark_read(true)
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    desc = "Restore theme-linked inbox highlights",
    callback = Render.highlights,
  })
  vim.api.nvim_create_autocmd("TabEnter", {
    group = group,
    desc = "Adapt the inbox when returning after an editor resize",
    callback = function()
      if vim.api.nvim_get_current_tabpage() == view.tab then
        layout(view)
        refresh(view)
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    desc = "Fit inbox list labels to the window width",
    callback = function()
      if vim.api.nvim_tabpage_is_valid(view.tab) and vim.api.nvim_win_is_valid(view.list_win) then
        if vim.api.nvim_get_current_tabpage() ~= view.tab then
          return
        end
        layout(view)
        Render.list(view)
        render_detail(view)
      end
    end,
  })
  refresh(view)
  local function poll()
    if view.closed or not vim.api.nvim_tabpage_is_valid(view.tab) then
      return
    end
    local win = vim.api.nvim_get_current_win()
    if
      vim.api.nvim_get_current_tabpage() == view.tab
      and vim.api.nvim_get_mode().mode == "n"
      and (win == view.list_win or win == view.source_win or win == view.thread_win)
      and view.stamp ~= stamp()
    then
      refresh(view)
    end
    vim.defer_fn(poll, 1500)
  end
  vim.defer_fn(poll, 1500)
  return view
end

return M
