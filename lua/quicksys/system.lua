local api, fn = vim.api, vim.fn
local quickfix = require("quicksys.quickfix")

local M = { default_handlers = {} }

local scheduled_echo = vim.schedule_wrap(function(ctx, chunks)
  if ctx.__msgchunks == nil then ctx.__msgchunks = {} end
  vim.list_extend(ctx.__msgchunks, chunks)
  ctx.__msgid = vim.api.nvim_echo(ctx.__msgchunks, false, { id = ctx.__msgid })
end)

M.system = function(...)
  if select("#", ...) == 0 then return end
  return M._system({}, ...)
end

---@param ctx quicksys.ContextObj
---@param ... quicksys.Command | quicksys.Command[] | quicksys.CommandSpec
function M._system(ctx, ...)
  local cmd
  local handlers = M.default_handlers
  local arg = select(1, ...)
  if type(arg) == "string" then
    cmd = vim.split(arg, " ")
  else
    assert(type(arg) == "table")
    if vim.islist(arg) then
      cmd = arg
    else
      cmd = type(arg.cmd) == "string" and vim.split(arg.cmd, " ") or arg.cmd
      local no_op_stub = function() end
      handlers = vim.tbl_deep_extend("force", handlers, {
        stdout = arg.stdout == false and no_op_stub or arg.stdout,
        stderr = arg.stderr == false and no_op_stub or arg.stderr,
        before = arg.before == false and no_op_stub or arg.before,
        after  = arg.after  == false and no_op_stub or arg.after,
        exit   = arg.exit   == false and no_op_stub or arg.exit,
      })
    end
  end

  ctx.__cmd = cmd
  if ctx.__cmds == nil then
    ctx.__system_objs = {}
    ctx.__idx = 0
    ctx.__cmds = vim
      .iter({ ... })
      :map(function(_arg)
        return type(_arg) == "string" and vim.split(_arg, " ")
               or vim.islist(_arg) and _arg
               or type(_arg.cmd) == "string" and vim.split(_arg.cmd,  " ")
               or _arg.cmd
      end)
      :totable()
  end
  ctx.__idx = ctx.__idx + 1

  handlers.before(ctx)

  local rest_of_args = { select(2, ...) }
  local on_exit = function(result)
    ctx.__end_time = vim.uv.hrtime()
    ctx.__end_times = ctx.__end_times or {}
    ctx.__end_times[#ctx.__end_times + 1] = ctx.__end_time

    handlers.exit(ctx, result)
    handlers.after(ctx, result)
    if #rest_of_args > 0 and result.code == 0 then
      M._system(ctx, unpack(rest_of_args))
    end
  end

  local ctx_wrap = function(fn)
    return function(...) fn(ctx, ...) end
  end

  ctx.__start_time = ctx.__start_time or vim.uv.hrtime()
  ctx.__start_times = ctx.__start_times or {}
  ctx.__start_times[#ctx.__start_times + 1] = ctx.__start_time
  local ok, ret = pcall(vim.system, cmd, {
    -- cwd = fn.getcwd(-1, -1, -1),
    text = true,
    stdout = ctx_wrap(handlers.stdout),
    stderr = ctx_wrap(handlers.stderr),
  }, on_exit)
  if ok then
    ctx.__system_objs[ctx.__idx] = ret
    return ctx
  else
    scheduled_echo(ctx, { { ret, "DiagnosticError" } })
  end
end

---@param ctx quicksys.ContextObj
---@param err any
---@param data any
M.default_handlers.stdout = function(ctx, err, data)
  if err then return vim.notify(err) end
  if data == nil then return end
  data = data:gsub("\r\n", "\n")
  local chunks = {{ data }}
  scheduled_echo(ctx, chunks)
end

---@param ctx quicksys.ContextObj
---@param err any
---@param data any
M.default_handlers.stderr = function(ctx, err, data)
  if err then return vim.notify(err) end
  if data == nil then return end
  data = data:gsub("\r\n", "\n")
  vim.schedule(function()
    local qf_context = vim.fn.getqflist({ context = true }).context
    -- NOTE: using __start_time as a unique id to tell if
    -- current quickfix list is the result of current context
    local current_quickfix_from_this_cmd =
      type(qf_context) == "table" and qf_context.__start_time == ctx.__start_time
    -- NOTE: this is perhaps unwanted behavior if chaining commands?
    if current_quickfix_from_this_cmd then
      return quickfix.append(ctx, data)
    end
    -- vim.print(vim.split(data, "\n"))
    -- otherwise create a new quickfix list for this context
    -- quickfix.close()
    -- quickfix.set(ctx, data)
  end)
end

---@param ctx quicksys.ContextObj
---@param result vim.SystemCompleted
M.default_handlers.exit = function(ctx, result)
  -- NOTE: no-op
end

---@param ctx quicksys.ContextObj
M.default_handlers.before = function(ctx)
  if ctx.__idx ~= 1 then return end

  local timestamp = os.date("%a %d %H:%M:%S", vim.uv.gettimeofday())
  local chunks = {
    { "System" },
    { "[", "@punctuation.bracket" },
    { "]", "@punctuation.bracket" },
    { " started at " },
    { timestamp, "Comment" },
  }
  for i = #ctx.__cmds, 1, -1 do
    local cmd = ctx.__cmds[i]
    table.insert(chunks, 3, { cmd[1], "Function" })
    if i > 1 then
      table.insert(chunks, 3, { " ➔ " })
    end
  end
  table.insert(chunks, { "\n\n" })
  scheduled_echo(ctx, chunks)
end

---@param ctx quicksys.ContextObj
---@param result vim.SystemCompleted
M.default_handlers.after = function(ctx, result)
  if ctx.__idx ~= #ctx.__cmds and result.code == 0 then
    return
  end

  local elapsed_s = (ctx.__end_time - ctx.__start_time) / 1e9
  local time_formatted = elapsed_s < 1 and ("%.2fms"):format(elapsed_s * 1000) or ("%.2fs"):format(elapsed_s)

  local chunks = ctx.__msgchunks and #ctx.__msgchunks > 0 and { { "\n" } } or {}
  if #ctx.__cmds > 1 then
    chunks[#chunks + 1] = { "[", "@punctuation.bracket" }
    chunks[#chunks + 1] = { "]", "@punctuation.bracket" }
  end
  vim.list_extend(chunks, {
    result.code == 0 and { " finished ", "DiagnosticOk" } or { " exited ", "DiagnosticError" },
    { ("in %s with code " ):format(time_formatted) },
    { tostring(result.code), "Number" },
  })
  for i = #ctx.__cmds, 1, -1 do
    local cmd = ctx.__cmds[i]
    local at = #ctx.__cmds > 1 and 3 or 2
    if result.code == 0 then
      table.insert(chunks, at, { cmd[1], "Function" })
      if i > 1 then
        table.insert(chunks, at, { " ✔ ", "DiagnosticOk" })
      end
    else
      local is_before_error = i <= ctx.__idx
      local is_after_error = i > ctx.__idx + 1
      table.insert(chunks, at, { cmd[1], is_before_error and "Function" or "Comment"})
      if i > 1 then
        table.insert(chunks, at, {
          is_after_error and " ➔ " or is_before_error and " ✔ " or " ✘ ",
          is_after_error and "Comment" or is_before_error and "DiagnosticOk" or "DiagnosticError"
        })
      end
    end
  end

  scheduled_echo(ctx, chunks)
end

---@alias quicksys.Command string | string[]

---@class quicksys.CommandSpec
---@field cmd quicksys.Command
---@field stdout? fun()
---@field stderr? fun()
---@field exit? fun()
---@field before? fun()
---@field after? fun()

---@class quicksys.ContextObj
---@field __cmd quicksys.Command current command being executed
---@field __cmds quicksys.Command[] list of all commands to be executed
---@field __idx integer index of current command in sequence
---@field __start_time integer vim.uv.hrtime when first command was executed
---@field __start_times integer[] start time for each command
---@field __end_time integer vim.uv.hrtime when current command exited
---@field __end_times integer[] end time for each command
---@field [any] any arbitrary user data to be passed through callbacks

return M
