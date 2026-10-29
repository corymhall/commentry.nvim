local Locations = require("commentry.inbox.locations")
local Render = require("commentry.inbox.render")
local Reply = require("commentry.inbox.reply")
local Source = require("commentry.inbox.source")
local Store = require("commentry.inbox.store")
local Util = require("commentry.util")
local M = {}
local active
local refresh

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
  local width = math.max(1, math.min(math.max(64, math.floor(vim.o.columns * 0.54)), vim.o.columns - 8))
  local height = math.max(1, math.min(math.max(8, math.floor(vim.o.lines * 0.24)), vim.o.lines - 6))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    border = "rounded",
    title = " " .. Render.clip(title, math.max(1, width - 4)) .. " ",
    title_pos = "center",
    footer = dispatch and " <C-s> save | <C-d> save + send | <Esc>/q cancel "
      or " Type freely | <C-s> save | <Esc>/q cancel ",
    footer_pos = "center",
    style = "minimal",
  })
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  vim.wo[win].wrap = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].cursorline = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].spell = false
  vim.wo[win].winbar = ""
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
  vim.keymap.set("n", "<CR>", function()
    submit(false)
  end, { buffer = buf, desc = "Save inbox message" })
  -- Insert-mode Escape still enters normal mode, where Enter saves.
  local function cancel()
    vim.cmd.stopinsert()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
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
      Util.info("Nothing new to send. There are no new messages.")
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
    local diffview = require("commentry.diffview")
    if diffview.get_current_view() then
      diffview.refresh()
    end
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
  Locations.set(view.location_threads or view.threads, thread and thread.id)
  if not thread then
    Render.remember_source(view)
    view.source_sections = nil
    Reply.remember(view)
    view.reply = nil
    write(view.source_buf, { "No threads in this scope.", "", ":Commentry comment", ":Commentry capture-text" }, "text")
    write(view.thread_buf, { "Capture code or text to start a conversation." }, "markdown")
    vim.bo[view.thread_buf].modified = false
    return
  end
  Render.selection(view, vim.api.nvim_win_get_cursor(view.list_win)[1])
  Render.source(view, thread, Source.sections(thread, view.context))
  vim.wo[view.source_win].winbar = " Source and changes %=%#CommentryInboxMuted#za fold  gl sections  gf code "
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
  view.location_threads = threads
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
  local scope_label = view.project and vim.fs.basename(view.project) or "All projects"
  vim.wo[view.list_win].winbar = " " .. scope_label:gsub("%%", "%%%%") .. " / " .. view.filter .. " / " .. #view.threads
  vim.wo[view.thread_win].winbar = " Conversation %=%#CommentryInboxMuted#"
    .. view.delivery_mode
    .. "  r reply  :w save  s send  gs all "
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
  Render.remember_source(view)
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
  vim.wo[view.source_win].winbar = " Source and changes %=%#CommentryInboxMuted#za fold  e context "
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
    active.filter = scope and scope ~= "" and scope ~= "all" and scope or "all"
    active.pin_id = nil
    layout(active)
    vim.wo[active.list_win].winbar = " Inbox / "
      .. (project and vim.fs.basename(project):gsub("%%", "%%%%") or "All projects")
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
    filter = scope and scope ~= "" and scope ~= "all" and scope or "all",
    delivery_mode = "queue",
    threads = {},
    origin_win = origin,
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
  vim.wo[view.source_win].winbar = " Source and changes %=%#CommentryInboxMuted#za fold  e context "
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
      Reply.focus(view)
    end
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
          if thread and not Reply.unsaved(view, nil, thread.id) then
            send_thread(thread.id, view.delivery_mode)
          end
        end,
        "Queue or send selected thread",
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
          local section = Render.source_section(view, vim.api.nvim_win_get_cursor(view.source_win)[1])
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
            "r       Focus the inline reply",
            "visual r  Quote a source selection into the reply",
            ":write  Save the reply, then s sends it",
            "n       New standalone project thread",
            "Enter   Open and mark read",
            "u       Toggle read/unread",
            "f       Filter threads",
            "m       Choose queue or steer mode",
            "s       Queue or send the selected thread",
            "gs      Send all new project comments to the agent queue",
            "S       Attach an existing project agent",
            "a       Attached agent status and delivery",
            "t       Retry a failed request",
            "d       Remove the oldest pending queue request",
            "Ctrl-d  Save and send from the composer",
            "Ctrl-h/j/k/l  Move between panels",
            "x       Resolve or reopen",
            "gl      Jump to a source section",
            "gf      Go to code, gC returns to its thread",
            "za      Fold or unfold a source section",
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
      if buf ~= view.thread_buf or vim.tbl_contains({ "r", "s", "gs", "q", "?", "gf", "gl" }, key) then
        vim.keymap.set("n", key, mapping[1], { buffer = buf, desc = mapping[2] })
      end
    end
    for key, direction in pairs({ h = "h", j = "j", k = "k", l = "l" }) do
      vim.keymap.set("n", "<C-" .. key .. ">", function()
        vim.cmd("wincmd " .. direction)
      end, { buffer = buf, desc = "Move to the " .. direction .. " panel" })
    end
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
