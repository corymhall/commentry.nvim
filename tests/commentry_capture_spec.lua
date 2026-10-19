---@module 'luassert'
local Store = require("commentry.inbox.store")

describe("external capture composer", function()
  local root, previous
  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    root = vim.uv.fs_realpath(root)
    previous = vim.env.COMMENTRY_INBOX_DIR
    vim.env.COMMENTRY_INBOX_DIR = root .. "/data"
  end)
  after_each(function()
    vim.env.COMMENTRY_INBOX_DIR = previous
    vim.fn.delete(root, "rf")
  end)

  local function run(actions)
    local repo = vim.fn.getcwd()
    local config = root .. "/capture.json"
    local options = {
      project = root,
      text = "Copied error\nwith context",
      directory = root .. "/data",
      executable = Store.executable(),
    }
    vim.fn.writefile({ vim.json.encode(options) }, config)
    local script = root .. "/exercise.lua"
    local code = {
      "dofile(vim.env.COMMENTRY_CAPTURE_SCRIPT)",
      "vim.cmd.stopinsert()",
      "local body = vim.api.nvim_get_current_buf()",
      "local keys = {}; for _, map in ipairs(vim.api.nvim_buf_get_keymap(body, 'n')) do keys[map.lhs] = map.callback end",
    }
    vim.list_extend(code, vim.split(actions, "\n", { plain = true }))
    vim.fn.writefile(code, script)
    return vim
      .system({ "nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l", script }, {
        text = true,
        env = { COMMENTRY_CAPTURE_CONFIG = config, COMMENTRY_CAPTURE_SCRIPT = repo .. "/capture/composer.lua" },
      })
      :wait(10000)
  end

  it("retains invalid drafts and saves the clipboard, multiline body and queue request", function()
    local result = run([[
      keys['<C-S>']()
      assert(vim.api.nvim_buf_is_valid(body), 'failed save closed the draft')
      vim.api.nvim_buf_set_lines(body, 0, -1, false, {'Explain this error', 'Can we make it clearer?'})
      keys['<C-D>']()
    ]])
    assert.are.same(0, result.code, result.stderr)
    local threads = assert(Store.list(root))
    assert.are.same(1, #threads)
    assert.are.same({ "Copied error", "with context" }, threads[1].source.lines)
    assert.are.same("Explain this error\nCan we make it clearer?", threads[1].messages[1].body)
    assert.are.same("pending", threads[1].queue[1].status)
  end)

  it("cancels without creating a thread", function()
    local result = run("keys.q()")
    assert.are.same(0, result.code, result.stderr)
    assert.are.same({}, assert(Store.list(root)))
  end)

  it("keeps delivery failures visible and does not resend an uncertain request", function()
    local result = run([[
      local system, attempts = vim.system, 0
      vim.system = function(argv, opts)
        local request = vim.json.decode(opts.stdin)
        if request.action == 'queue' then
          attempts = attempts + 1
          return {wait=function() return {code=0,stdout=vim.json.encode({ok=true,result={delivery_error='Acceptance is unknown'}})} end}
        end
        return system(argv, opts)
      end
      vim.api.nvim_buf_set_lines(body, 0, -1, false, {'A saved comment with uncertain delivery'})
      keys['<C-D>']()
      assert(vim.api.nvim_buf_is_valid(body), 'delivery failure closed the composer')
      assert(vim.wo.statusline:find('delivery failed',1,true), 'failure is hidden')
      keys['<C-D>']()
      assert(attempts == 1, 'repeated Ctrl-d resubmitted uncertain delivery')
      keys['<C-S>']()
    ]])
    assert.are.same(0, result.code, result.stderr)
    local threads = assert(Store.list(root))
    assert.are.same(1, #threads)
    assert.are.same("A saved comment with uncertain delivery", threads[1].messages[1].body)
  end)
end)
