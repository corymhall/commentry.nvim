-- Load from Rex init.lua. Requires commentry on PATH.
local function launch(ctx, command, empty)
  local args = {
    "commentry",
    "rex",
    "--session",
    ctx.session_id,
    "--block",
    ctx.block_id,
    "--client",
    ctx.client_id,
    "--defer-focus",
    command,
  }
  if empty then
    args[#args + 1] = "--empty"
  end
  local result, err = rex.exec(args)
  if not result then
    error(err)
  end
  if not result.ok then
    error(result.stderr ~= "" and result.stderr or result.stdout)
  end
  local response, decode_err = rex.json.decode(result.stdout)
  if not response or not response.ok then
    error(decode_err or "Unable to open Commentry")
  end
  local waited, wait_err = rex.exec({ "sleep", "0.2" })
  if not waited or not waited.ok then
    error(wait_err or "Unable to select Commentry")
  end
  rex.client.queue("session.select", { session_id = ctx.session_id, window_id = response.result.window })
end
rex.action({
  name = "commentry_capture",
  title = "Comment on Clipboard",
  run = function(ctx)
    launch(ctx, "capture", false)
  end,
})
rex.action({
  name = "commentry_new",
  title = "New Inbox Comment",
  run = function(ctx)
    launch(ctx, "capture", true)
  end,
})
-- These actions are also available in the command palette. Bind your preferred
-- keys in init.lua, for example rex.bind("super+shift+m", "commentry_capture").

rex.action({
  name = "commentry_inbox",
  title = "Open Project Inbox",
  run = function(ctx)
    launch(ctx, "inbox", false)
  end,
})
