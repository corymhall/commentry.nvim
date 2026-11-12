local Locations = require("commentry.inbox.locations")
local Render = require("commentry.inbox.render")
local Reply = require("commentry.inbox.reply")
local Source = require("commentry.inbox.source")
local Store = require("commentry.inbox.store")
local UI = require("commentry.inbox.ui")
local Util = require("commentry.util")
local M = {}
local active
local refresh
local layout

local function close_view(view)
  Reply.remember(view)
  view.reply = nil
  if vim.api.nvim_buf_is_valid(view.thread_buf) then
    vim.bo[view.thread_buf].modified = false
  end
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
  -- The optional source buffer survives while its panel is hidden.
  if vim.api.nvim_buf_is_valid(view.source_buf) then
    vim.api.nvim_buf_delete(view.source_buf, { force = true })
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
      "Revision " .. (thread.source.git.revision or "capture from editor"),
      "Blob     " .. (thread.source.git.blob or "uncommitted file"),
      "Buffer   " .. (thread.source.modified and "Unsaved changes captured" or "Saved file captured"),
    })
  end
  return rows
end

local function details(rows)
  local popup = UI.popup({ title = "Commentry", height = #rows, footer = "q / Esc close" })
  if not popup then
    return
  end
  local buf = popup.bufnr
  write(buf, rows, "text")
  Render.mark(buf, 0, "Title")
  for _, key in ipairs({ "q", "<Esc>" }) do
    popup:map("n", key, function()
      popup:unmount()
    end, { desc = "Close inbox details" })
  end
end

-- A real buffer keeps multiline editing and save/cancel behavior predictable.
local function compose(title, initial, save, dispatch)
  local popup = UI.popup({
    title = title,
    width = math.min(100, math.max(60, math.floor(vim.o.columns * 0.6))),
    height = math.max(6, math.floor(vim.o.lines * 0.35)),
    filetype = "markdown",
    footer = dispatch and "Ctrl-s save / Ctrl-d send / Esc cancel" or "Ctrl-s save / Esc cancel",
  })
  if not popup then
    return
  end
  local buf, win = popup.bufnr, popup.winid
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
        popup:unmount()
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
  vim.keymap.set("n", "<CR>", function()
    submit(false)
  end, { buffer = buf, desc = "Save inbox message" })
  -- Insert-mode Escape still enters normal mode, where Enter saves.
  local function cancel()
    vim.cmd.stopinsert()
    if vim.api.nvim_win_is_valid(win) then
      popup:unmount()
    end
  end
  for _, key in ipairs({ "q", "<Esc>", "<C-c>" }) do
    vim.keymap.set("n", key, cancel, { buffer = buf, desc = "Cancel inbox message" })
  end
  vim.cmd.startinsert()
end

local function send_thread(id, mode)
  local result, err = require("commentry.inbox.agent").send(id, mode)
  if not report(result, err) then
    return
  end
  if not result.delivery_error then
    if result.skipped then
      Util.info("Nothing new to send. Use gn to notify again about outstanding work.")
    else
      Util.info(
        mode == "queue" and (result.status == "claimed" and "Sent to the agent queue" or "Saved for delivery")
          or "Steering submitted"
      )
    end
  end
  if active and vim.api.nvim_tabpage_is_valid(active.tab) then
    refresh(active)
  end
end

local function refresh_code(project)
  local diffview = require("commentry.diffview")
  if diffview.current_file_context() then
    diffview.refresh()
  else
    local threads, err = Store.list(project)
    if report(threads, err) then
      Render.highlights()
      require("commentry.inbox.locations").set(threads)
    end
  end
end

local function edit_pending_comment(thread, saved)
  if not thread.pending then
    Util.warn("Only pending comments can be edited. Sent conversations use replies.")
    return
  end
  local version = thread.messages[1].id
  compose("Edit pending comment", vim.split(thread.messages[1].body, "\n", { plain = true }), function(body)
    local event, err = Store.update(thread.id, { kind = "edit-pending", body = body, expected_message = version })
    if not report(event, err) then
      return false
    end
    saved(thread)
    return thread.id
  end)
end

function M.new_thread()
  local view = active and vim.api.nvim_get_current_tabpage() == active.tab and active or nil
  local project = view and view.project or Source.project()
  compose("New project thread", nil, function(body)
    local id, err = Store.create({
      project = project,
      body = body,
      pending = true,
      source = { kind = "text", lines = {}, origin = "general" },
    })
    if not report(id, err) then
      return false
    end
    if view then
      view.filter = "open"
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
    capture.pending = true
    local id, create_err = Store.create(capture)
    if not report(id, create_err) then
      return false
    end
    Util.info("Saved inbox thread " .. id)
    refresh_code(capture.project)
    return true
  end)
end

function M.edit()
  require("commentry.inbox.locations").choose_at_cursor(function(candidate)
    if not candidate then
      return
    end
    local thread, err = Store.get(candidate.id)
    if report(thread, err) then
      edit_pending_comment(thread, function()
        refresh_code(thread.project)
      end)
    end
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
    capture.pending = true
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
  Locations.set(view.location_threads or view.threads, thread and thread.id)
  if not thread then
    Render.remember_source(view)
    view.source_sections = nil
    Render.clear_conversation(view)
    Reply.remember(view)
    view.reply = nil
    view.detail_thread = nil
    layout(view, false)
    write(view.thread_buf, {
      "",
      "  No threads in this scope",
      "",
      "  n   Start a project conversation",
      "  f   Choose another filter",
      "",
      "  Capture code with :Commentry comment",
      "  Capture text with :Commentry capture-text",
    }, "markdown")
    Render.mark(view.thread_buf, 1, "Title")
    vim.bo[view.thread_buf].modified = false
    return
  end
  Render.selection(view, vim.api.nvim_win_get_cursor(view.list_win)[1])
  local sections = Source.sections(thread, view.context)
  -- Sections include a placeholder for unanchored conversations. A file location
  -- is still useful when unavailable, but empty text alone should not open a pane.
  local has_source = false
  for _, section in ipairs(sections) do
    if
      (section.source and section.source.kind == "file") or table.concat(section.comparison.lines, "\n"):find("%S")
    then
      has_source = true
      break
    end
  end
  layout(view, has_source)
  if has_source then
    Render.source(view, thread, sections)
  else
    view.source_sections = {}
    view.source_thread = nil
  end
  Render.conversation(view, thread)
  if view.detail_thread ~= thread.id then
    -- A shorter thread must not inherit a previous conversation's scroll offset.
    vim.api.nvim_win_call(view.thread_win, function()
      vim.fn.winrestview({ topline = 1, lnum = 1, col = 0, leftcol = 0, skipcol = 0 })
    end)
    view.detail_thread = thread.id
  end
  UI.headers(view)
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
  -- Direct navigation may deliberately visit an already resolved thread.
  -- Do not pin an open thread, so resolving it removes it from the default view.
  if view.filter == "open" and select_id then
    for _, thread in ipairs(threads) do
      if thread.id == select_id and thread.resolved then
        view.pin_id = select_id
      end
    end
  end
  view.threads, view.outdated = threads, {}
  view.location_threads = threads
  view.threads = vim.tbl_filter(function(thread)
    if view.filter == "unread" then
      return thread.unread or view.pin_id == thread.id
    end
    if view.filter == "read" then
      return not thread.unread
    end
    if view.filter == "open" then
      return not thread.resolved or view.pin_id == thread.id
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
    local _, outdated = Source.sections(thread, view.context)
    view.outdated[thread.id] = outdated
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
  UI.headers(view)
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
  vim.wo.list = false
  vim.wo.signcolumn = "no"
  vim.wo.wrap = true
  vim.wo.linebreak = true
  vim.wo.breakindent = true
  vim.wo.cursorline = false
  vim.wo.fillchars = "eob: ,fold: "
  vim.wo.statusline = "%#CommentryInboxMuted#%=%l / %L "
  return vim.api.nvim_get_current_win()
end

layout = function(view, has_source)
  if view.closed then
    return
  end
  if has_source == nil then
    has_source = view.has_source or false
  end
  local wide = vim.o.columns >= 140
  local focus = vim.api.nvim_get_current_win()
  local focus_source = focus == view.source_win
  local focus_list = focus == view.list_win
  local rebuild_source = view.has_source ~= has_source or view.wide ~= wide
  local resized = view.columns ~= vim.o.columns or view.lines ~= vim.o.lines
  -- Selection and refresh should preserve native resizing and restored zoom sizes.
  if not rebuild_source and (view.zoomed or not resized) then
    return
  end
  view.reflowing = true
  if rebuild_source then
    view.zoomed = false
    Render.remember_source(view)
    if vim.api.nvim_win_is_valid(view.source_win or -1) then
      vim.api.nvim_win_close(view.source_win, true)
    end
    view.source_win = -1
  end
  if not vim.api.nvim_win_is_valid(view.thread_win or -1) then
    vim.api.nvim_set_current_win(view.list_win)
    vim.cmd("rightbelow vsplit")
    view.thread_win = window(view.thread_buf)
  end
  if has_source and not vim.api.nvim_win_is_valid(view.source_win) then
    vim.api.nvim_set_current_win(view.thread_win)
    vim.cmd(wide and "rightbelow vsplit" or "rightbelow split")
    view.source_win = window(view.source_buf)
  end
  local list_width = math.min(48, math.max(24, math.floor(vim.o.columns * 0.22)))
  vim.api.nvim_win_set_width(view.list_win, list_width)
  if has_source then
    if wide then
      vim.api.nvim_win_set_width(view.source_win, math.floor((vim.o.columns - list_width - 2) * 0.5))
    else
      vim.api.nvim_win_set_height(view.source_win, math.max(3, math.floor((vim.o.lines - 6) * 0.45)))
    end
  end
  view.wide, view.has_source = wide, has_source
  view.columns, view.lines = vim.o.columns, vim.o.lines
  UI.headers(view)
  local target = focus_source and has_source and view.source_win or focus_list and view.list_win or view.thread_win
  -- Changing the window tree is a preview update, not an explicit read action.
  vim.api.nvim_set_current_win(target)
  view.reflowing = false
end

function M.open(scope, opts)
  local origin = vim.api.nvim_get_current_win()
  Render.highlights()
  if active and active.closed then
    close_view(active)
  end
  local project = Source.project(opts and opts.project)
  if scope == "all" then
    project = nil
  end
  if active and vim.api.nvim_tabpage_is_valid(active.tab) then
    vim.api.nvim_set_current_tabpage(active.tab)
    active.project = project
    active.filter = scope and scope ~= "" and scope ~= "all" and scope or "open"
    active.pin_id = nil
    layout(active)
    refresh(active, opts and opts.thread)
    if vim.api.nvim_win_is_valid(origin) and vim.bo[vim.api.nvim_win_get_buf(origin)].buftype == "" then
      active.origin_win = origin
    end
    return active
  end
  vim.cmd.tabnew()
  local view = {
    tab = vim.api.nvim_get_current_tabpage(),
    project = project,
    context = 4,
    filter = scope and scope ~= "" and scope ~= "all" and scope or "open",
    source_win = -1,
    delivery_mode = "queue",
    threads = {},
    origin_win = origin,
    outdated = {},
    list_buf = scratch("commentry://inbox"),
    source_buf = scratch("commentry://source"),
    thread_buf = scratch("commentry://thread"),
  }
  active = view
  vim.bo[view.source_buf].bufhidden = "hide"
  view.list_win = window(view.list_buf)
  layout(view)
  UI.headers(view)
  vim.wo[view.list_win].wrap = false
  vim.wo[view.list_win].scrolloff = 2
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
  local function edit_pending()
    local thread = selected(view)
    if not thread or not thread.pending then
      Util.warn("Only pending comments can be edited. Sent conversations use replies.")
      return
    end
    if Reply.unsaved(view, nil, thread.id) then
      return
    end
    edit_pending_comment(thread, function()
      refresh(view, thread.id)
    end)
  end
  local function reply()
    local thread = selected(view)
    if thread then
      if thread.pending then
        edit_pending()
      else
        Reply.focus(view)
      end
    end
  end
  local function discard_pending()
    local thread = selected(view)
    if not thread or not thread.pending then
      Util.warn("Only pending comments can be discarded")
      return
    end
    if Reply.unsaved(view, nil, thread.id) then
      return
    end
    local version = thread.messages[1].id
    vim.ui.select({ "Keep", "Discard" }, { prompt = "Discard pending comment?" }, function(choice)
      if choice == "Discard" then
        local event, err = Store.update(thread.id, { kind = "discard-pending", expected_message = version })
        if report(event, err) and not view.closed then
          refresh(view)
        end
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
    -- A dirty inline reply still displays its saved history. Never acknowledge
    -- a newer incoming version that has not been rendered beneath that draft.
    local seen = thread.incoming
    if read and view.reply and view.reply.id == thread.id then
      seen = view.reply.incoming
      if not seen and thread.incoming then
        return
      end
    end
    local event, err = Store.update(thread.id, { kind = "read", read = read, seen = seen })
    if report(event, err) then
      thread.unread = not read or thread.incoming ~= seen
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
  local function find_thread()
    require("commentry.inbox.picker").open(view.threads, function(id)
      if not view.closed and vim.api.nvim_win_is_valid(view.list_win) then
        vim.api.nvim_set_current_win(view.list_win)
        refresh(view, id)
      end
    end)
  end
  local function zoom()
    if view.zoomed then
      vim.cmd(view.zoom_restore)
      view.zoomed = false
      layout(view)
    else
      view.zoom_restore = vim.fn.winrestcmd()
      view.zoomed = true
      vim.cmd("wincmd |")
      vim.cmd("wincmd _")
    end
    Render.list(view)
    render_detail(view)
  end
  vim.keymap.set("n", "/", find_thread, { buffer = view.list_buf, desc = "Find inbox conversation" })
  for _, buf in ipairs({ view.list_buf, view.source_buf, view.thread_buf }) do
    for key, mapping in pairs({
      ["g/"] = { find_thread, "Find inbox conversation" },
      gz = { zoom, "Maximize or restore inbox panel" },
      q = { close, "Close inbox" },
      R = {
        function()
          view.pin_id = nil
          refresh(view)
        end,
        "Refresh inbox",
      },
      r = { reply, "Reply or edit pending comment" },
      ge = { edit_pending, "Edit pending comment" },
      gd = { discard_pending, "Discard pending comment" },
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
          if thread and not Reply.unsaved(view, nil, thread.id) then
            send_thread(thread.id, view.delivery_mode)
          end
        end,
        "Queue or send selected thread",
      },
      gn = {
        function()
          local thread = selected(view)
          if not thread then
            return
          end
          for _, item in ipairs(thread.queue) do
            if item.status == "claimed" or item.status == "failed" then
              local choices = { "Notify again", "Hand off to selected agent", "Cancel" }
              vim.ui.select(
                choices,
                { prompt = "Remind the agent, or invalidate the old claim for a handoff?" },
                function(choice)
                  if not choice or choice == "Cancel" then
                    return
                  end
                  local args = { "agent", "--project", thread.project, "notify", thread.id, "--queue-id", item.id }
                  if choice == "Hand off to selected agent" then
                    args[#args + 1] = "--handoff"
                  end
                  local result, err = Store.command(args)
                  if report(result, err) then
                    Util.info("Notification submitted. This does not prove the agent fetched it.")
                    if vim.api.nvim_tabpage_is_valid(view.tab) then
                      refresh(view)
                    end
                  end
                end
              )
              return
            end
          end
          Util.info("No outstanding submitted request. Use s to send new comments.")
        end,
        "Notify again or explicitly hand off an outstanding request",
      },
      gs = {
        function()
          local target_project = view.project or (selected(view) and selected(view).project)
          if not target_project then
            Util.warn("Select a project thread first")
            return
          end
          if Reply.unsaved(view, target_project) then
            return
          end
          local result, err = require("commentry.inbox.agent").send_all(target_project)
          if not report(result, err) then
            return
          end
          refresh(view)
          if result.failed > 0 then
            Util.warn(
              ("Sent %d thread(s), saved %d for delivery, %d need attention.\n"):format(
                result.sent,
                result.queued,
                result.failed
              ) .. table.concat(result.errors, "\n")
            )
          elseif result.queued > 0 then
            Util.warn(
              ("Sent %d thread(s). %d queued, not delivered. Press S in the inbox to attach a running project agent.\n"):format(
                result.sent,
                result.queued
              ) .. ("Skipped %d unchanged or resolved."):format(result.skipped)
            )
          elseif result.sent == 0 then
            Util.info("Nothing new to send. There are no new comments.")
          else
            Util.info(
              ("Sent %d thread(s), saved %d for delivery, skipped %d unchanged or resolved."):format(
                result.sent,
                result.queued,
                result.skipped
              )
            )
          end
        end,
        "Send all new project comments to the agent queue",
      },
      S = {
        function()
          local target_project = view.project or (selected(view) and selected(view).project)
          if not target_project then
            Util.warn("Select a project thread first")
            return
          end
          require("commentry.inbox.agent").choose(target_project)
        end,
        "Attach an existing project agent",
      },
      a = {
        function()
          local target_project = view.project or (selected(view) and selected(view).project)
          if target_project then
            require("commentry.inbox.agent").controls(target_project)
          end
        end,
        "Attached agent status and delivery",
      },
      t = {
        function()
          local thread = selected(view)
          if not thread then
            return
          end
          for _, item in ipairs(thread.queue) do
            if item.status == "failed" then
              vim.ui.select(
                { "Keep failed", "Retry request" },
                { prompt = item.error or "Inspect partial work before retrying" },
                function(choice)
                  if choice == "Retry request" then
                    update({ kind = "retry", queue_id = item.id })
                  end
                end
              )
              return
            end
          end
          Util.info("No failed requests in this thread")
        end,
        "Retry a failed request after inspecting partial work",
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
      gl = {
        function()
          local thread = selected(view)
          if not thread then
            return
          end
          if not vim.api.nvim_win_is_valid(view.source_win) then
            Util.info("This conversation has no source sections")
            return
          end
          vim.ui.select(view.source_sections, {
            prompt = "Source sections",
            format_item = function(item)
              return item.title
            end,
          }, function(item)
            if item and vim.api.nvim_win_is_valid(view.source_win) then
              for _, current in ipairs(view.source_sections or {}) do
                if current.id == item.id then
                  vim.api.nvim_set_current_win(view.source_win)
                  vim.api.nvim_win_set_cursor(view.source_win, { current.first, 0 })
                  vim.cmd("normal! zv")
                  break
                end
              end
            end
          end)
        end,
        "Jump to a source section",
      },
      gf = {
        function()
          local thread = selected(view)
          if not thread then
            return
          end
          local row = vim.api.nvim_win_is_valid(view.source_win) and vim.api.nvim_win_get_cursor(view.source_win)[1]
            or 1
          local section = Render.source_section(view, row)
          -- Outside the source pane, default to the first code section rather
          -- than assigning a file to an unrelated saved comparison.
          if vim.api.nvim_get_current_win() ~= view.source_win and (not section or not section.source) then
            for _, item in ipairs(view.source_sections or {}) do
              if item.source and item.source.kind == "file" then
                section = item
                break
              end
            end
          end
          if not section or not section.source or section.source.kind ~= "file" then
            Util.warn("This section has no code location. Use gl to choose a code section.")
            return
          end
          local ok, err = Locations.jump(vim.tbl_extend("force", thread, { source = section.source }), view.origin_win)
          if ok then
            view.origin_win = vim.api.nvim_get_current_win()
          else
            Util.warn(err)
          end
        end,
        "Go to code for the source section",
      },
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
            "r       Edit pending comment or focus the inline reply",
            "ge      Edit a pending comment before sending",
            "gd      Discard a pending comment",
            "visual r  Quote a source selection into the reply",
            ":write  Save the reply, then s sends it",
            "n       New standalone project thread",
            "Enter   Open and mark read",
            "u       Toggle read/unread",
            "f       Filter threads",
            "m       Choose queue or steer mode",
            "s       Queue or send the selected thread",
            "gs      Send all new project comments to the agent queue",
            "gn      Notify again or explicitly hand off outstanding work",
            "S       Attach an existing project agent",
            "a       Attached agent status and delivery",
            "t       Retry a failed request",
            "d       Remove the oldest pending queue request",
            "Ctrl-d  Save and send from the composer",
            "Ctrl-h/j/k/l  Move between panels",
            "Tab / Shift-Tab  Cycle panels",
            "/ in list, g/ anywhere  Find a conversation",
            "gz      Maximize or restore the current panel",
            "x       Resolve or reopen",
            "gl      Jump to a source section",
            "gf      Go to code, gC returns to its thread",
            "za      Fold or unfold a message or source section",
            "zR      Expand all messages or source sections",
            "e       Expand or collapse code context",
            "i       Inspect capture and Git details",
            "R       Refresh",
            "q       Close inbox",
          })
        end,
        "Show inbox help",
      },
    }) do
      -- The conversation is an editor now. Leave insert, append, undo, change,
      -- delete and other ordinary text keys available in its normal mode.
      if
        buf ~= view.thread_buf
        or vim.tbl_contains({ "r", "ge", "gd", "s", "gs", "q", "?", "gf", "gl", "g/", "gz" }, key)
      then
        vim.keymap.set("n", key, mapping[1], { buffer = buf, desc = mapping[2] })
      end
    end
    for key, step in pairs({ ["<Tab>"] = 1, ["<S-Tab>"] = -1 }) do
      vim.keymap.set("n", key, function()
        local wins = { view.list_win, view.thread_win }
        if vim.api.nvim_win_is_valid(view.source_win) then
          wins[#wins + 1] = view.source_win
        end
        local index = vim.fn.index(wins, vim.api.nvim_get_current_win())
        vim.api.nvim_set_current_win(wins[(index + step) % #wins + 1])
      end, { buffer = buf, desc = "Cycle inbox panels" })
    end
    for key, direction in pairs({ h = "h", j = "j", k = "k", l = "l" }) do
      vim.keymap.set("n", "<C-" .. key .. ">", function()
        vim.cmd("wincmd " .. direction)
      end, { buffer = buf, desc = "Move to the " .. direction .. " panel" })
    end
  end
  for _, key in ipairs({ "za", "zA", "zo", "zO", "zc", "zC", "zr", "zm", "zR", "zM" }) do
    local command = key
    vim.keymap.set("n", key, function()
      local count = vim.v.count > 0 and tostring(vim.v.count) or ""
      vim.cmd("normal! " .. count .. command)
      Render.decorate_conversation(view)
    end, { buffer = view.thread_buf, desc = "Update message headers after " .. key })
  end
  local group = vim.api.nvim_create_augroup("CommentryInbox", { clear = true })
  view.group = group
  vim.bo[view.thread_buf].buftype = "acwrite"
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = view.thread_buf,
    desc = "Save the inline inbox reply without changing conversation history",
    callback = function()
      local id = view.reply and view.reply.id
      if Reply.save(view) then
        refresh(view, id)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = view.thread_buf,
    desc = "Retain an inline draft when its conversation buffer closes",
    callback = function()
      Reply.remember(view)
    end,
  })
  vim.keymap.set("x", "r", function()
    local thread = selected(view)
    if thread and thread.pending then
      Util.warn("Send the pending comment before quoting into a reply. Use ge to edit it.")
      return
    end
    local first, last = vim.fn.getpos("v"), vim.fn.getpos(".")
    local lines = vim.fn.getregion(first, last, {
      type = vim.fn.mode(),
      exclusive = vim.o.selection == "exclusive",
    })
    local low, high = math.min(first[2], last[2]), math.max(first[2], last[2])
    local labels = {}
    for _, section in ipairs(view.source_sections or {}) do
      if low <= section.last and high >= section.first then
        local source = section.source
        labels[#labels + 1] = source
            and source.path
            and ((section.id == "original" and "Original context / " or "") .. source.path)
          or section.title
      end
    end
    if #labels > 0 then
      table.insert(lines, 1, table.concat(labels, "; "))
    end
    vim.cmd.normal({ args = { "\27" }, bang = true })
    if selected(view) then
      Reply.focus(view, lines)
    end
  end, { buffer = view.source_buf, desc = "Quote source selection in an inline reply" })
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
  refresh(view, opts and opts.thread)
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
