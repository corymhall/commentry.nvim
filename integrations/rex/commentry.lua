-- Load from Rex init.lua. GUI-launched Rex may have only a system PATH.
local function command_environment()
  local path = os.getenv("PATH") or "/usr/bin:/bin"
  local home = os.getenv("HOME")
  if home and home ~= "" then
    path = path .. ":" .. home .. "/.local/bin"
  end
  local rex_bin = os.getenv("REX_BIN_DIR")
  if (not rex_bin or rex_bin == "") and home and home ~= "" then
    -- Rex injects REX_BIN_DIR into terminals, but its config actions may not
    -- inherit it. Use the managed macOS install's stable Current path.
    rex_bin = home
      .. "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS"
  end
  if rex_bin and rex_bin ~= "" then
    path = path .. ":" .. rex_bin
  end
  -- The CLI also starts Neovim. Include both standard Homebrew prefixes
  -- without invoking a login shell or interpolating action arguments.
  path = path .. ":/opt/homebrew/bin:/usr/local/bin"
  return { PATH = path }
end
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
  local result, err = rex.exec(args, { env = command_environment() })
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
