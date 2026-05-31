local fn = vim.fn
local uv = vim.uv

local quickfix = require("quicksys.quickfix")
local output = require("quicksys.output").win

local M = {}

local function on_stdout(ctx, err, data)
  if err then return vim.print(err) end
  if data == nil then return end
  data = data:gsub("\n$", "") -- remove annoying trailing newline
  local lines = vim.split(data, "\n")
  vim.schedule(function()
    vim.cmd.cclose()
    output(ctx)
      :open()
      :append_lines(lines, true)
  end)
end

local function on_stderr(ctx, err, data)
  if err then return vim.print(err) end
  if data == nil then return end
  data = data:gsub("\n$", "") -- remove annoying trailing newline
  vim.schedule(function()
    local qf_context = vim.fn.getqflist({ context = true }).context
    -- NOTE: using __start_time as a unique id to tell if
    -- current quickfix list is the result of current Syscall
    local current_quickfix_from_this_cmd = type(qf_context) == "table" and qf_context.__start_time == ctx.__start_time
    -- NOTE: this is perhaps unwanted behavior if chaining commands?
    if current_quickfix_from_this_cmd then
      return quickfix.append(ctx, data)
    end
    -- otherwise create a new quickfix list for this context
    quickfix.close()
    quickfix.set(ctx, data)
  end)
end

local function on_exit(ctx, obj)
  local end_time = uv.hrtime()
  ctx.__end_time = end_time
  ctx.__end_times = ctx.__end_times or {}
  table.insert(ctx.__end_times, ctx.__end_time)

  vim.schedule(function()
    local qf_context = fn.getqflist({ context = true }).context
    local current_quickfix_from_this_cmd = type(qf_context) == "table" and qf_context.__start_time == ctx.__start_time
    if not current_quickfix_from_this_cmd then return end
    qf_context.__end_time = end_time
    fn.setqflist({}, "r", { context = qf_context })
    if obj.code == 0 then
      quickfix.replace(ctx, "")
      quickfix.close()
    end
  end)
end

local function before(ctx)
  if ctx.__idx ~= 1 then return end

  local cmds = ctx.__cmds
  vim.schedule(function()
    quickfix.close()

    local timestamp = os.date("%a %d %H:%M:%S", uv.gettimeofday())
    local chunks = {
      "System",
      { "[", "@punctuation.bracket" },
      { "]", "@punctuation.bracket" },
      " started at ",
      { timestamp, "Comment" },
    }
    for i = #cmds, 1, -1 do
      local cmd = cmds[i]
      table.insert(chunks, 3, { cmd[1], "Function" })
      if i > 1 then
        table.insert(chunks, 3, { " ➔ ", "Normal" })
      end
    end
    output()
      :open()
      :set_lines({}, { force = true })
      :append_lines({ chunks, "" }, true)
  end)
end

local function after(ctx, obj)
  if ctx.__idx ~= #ctx.__cmds and obj.code == 0 then
    return
  end

  local cmds = ctx.__cmds
  local elapsed = (ctx.__end_time - ctx.__start_time) / 1e9
  vim.schedule(function()
    local chunks = {
      { #ctx.__cmds > 1 and "[" or "", "@punctuation.bracket" },
      { #ctx.__cmds > 1 and "]" or "", "@punctuation.bracket" },
      obj.code == 0 and { " finished ", "DiagnosticOk" } or { " exited ", "DiagnosticError" },
      { ("in %.3fs with code " ):format(elapsed) },
      { tostring(obj.code), "Number" },
    }
    for i = #cmds, 1, -1 do
      local cmd = cmds[i]
      if obj.code == 0 then
        table.insert(chunks, 2, { cmd[1], "Function" })
        if i > 1 then
          table.insert(chunks, 2, { " ✔ ", "DiagnosticOk" })
        end
      else
        local before_error = i <= ctx.__idx
        local after_error = i > ctx.__idx + 1
        table.insert(chunks, 2, { cmd[1], before_error and "Function" or "Comment"})
        if i > 1 then
          table.insert(chunks, 2, {
            after_error and " ➔ " or before_error and " ✔ " or " ✘ ",
            after_error and "Comment" or before_error and "DiagnosticOk" or "DiagnosticError"
          })
        end
      end
    end
    local lines = { chunks }
    if output():get_line(-1) ~= "" then
      table.insert(lines, 1, "")
    end
    output(ctx)
      :open()
      :append_lines(lines, true)
  end)
end

M.default_handlers = {
  stdout = on_stdout,
  stderr = on_stderr,
  exit = on_exit,
  before = before,
  after = after,
}

function M.system(ctx, ...)
  -- TODO: handle vargs with shape
  -- system(ctx, "cmd1", "cmd2")
  -- system(ctx, { cmd = "cmd1", stdout = ... }, "cmd2")
  -- system(ctx,
  --   { cmd = "cmd1", stdout = ... },
  --   { cmd = "cmd2", before = ..., after = ... })
  if select("#", ...) == 0 then return end

  local cmd = select(1, ...)
  cmd = type(cmd) == "string" and vim.split(cmd, " ") or cmd
  ctx = ctx or {}
  ctx.__cmd = cmd

  if ctx.__cmds == nil then
    ctx.__idx = 0
    ctx.__cmds = vim
      .iter({...})
      :map(function(_cmd)
        return type(_cmd) == "string" and vim.split(_cmd, " ") or _cmd
      end)
      :totable()
  end
  ctx.__idx = ctx.__idx + 1

  local handlers = vim.tbl_deep_extend("force", M.default_handlers, {})

  local ctx_wrap = function(f, _after)
    return function(...)
      f(ctx, ...)
      if _after then _after(ctx, ...) end
    end
  end

  local rest_of_args = { select(2, ...) }
  ---@diagnostic disable-next-line: redefined-local
  local on_exit
  if #rest_of_args > 0 then
    on_exit = function(obj)
      handlers.exit(ctx, obj)
      if handlers.after then
        handlers.after(ctx, obj)
      end
      if obj.code == 0 then
        M.system(ctx, unpack(rest_of_args))
      end
    end
  else
    on_exit = ctx_wrap(handlers.exit, handlers.after)
  end

  handlers.before(ctx)

  ctx.__start_time = ctx.__start_time == nil and uv.hrtime() or ctx.__start_time
  ctx.__start_times = ctx.__start_times or {}
  table.insert(ctx.__start_times, ctx.__start_time)

  return vim.system(cmd, {
    text = true,
    stdout = ctx_wrap(handlers.stdout),
    stderr = ctx_wrap(handlers.stderr),
  }, on_exit)
end

return M
