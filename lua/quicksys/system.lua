local api, fn = vim.api, vim.fn
local quickfix = require("quicksys.quickfix")
local Parser = require("quicksys.ansi_parser")
local util = require("quicksys.util")

local M = { default_handlers = {} }

local scheduled_echo = vim.schedule_wrap(function(ctx, chunks)
  if ctx.__msgchunks == nil then ctx.__msgchunks = {} end
  vim.list_extend(ctx.__msgchunks, chunks)
  ctx.__msgid = vim.api.nvim_echo(ctx.__msgchunks, false, { id = ctx.__msgid })
end)

local ns = api.nvim_create_namespace("")
local win
local scheduled_append = vim.schedule_wrap(function(ctx, chunks)
  if ctx.__lines == nil then ctx.__lines = {} end
  if ctx.__outbuf == nil then ctx.__outbuf = api.nvim_create_buf(false, true) end

  local base = (#ctx.__lines > 0) and (#ctx.__lines - 1) or 0
  local lines, extmarks = util.chunks_to_lines(chunks, base)

  local start
  if #ctx.__lines > 0 then
    ctx.__lines[#ctx.__lines] = ctx.__lines[#ctx.__lines] .. table.remove(lines, 1)
    start = #ctx.__lines - 1
  else
    start = 0
  end
  vim.list_extend(ctx.__lines, lines)
  api.nvim_buf_set_lines(ctx.__outbuf, start, -1, false,
                        vim.list_slice(ctx.__lines, start + 1))

  for _, extmark in ipairs(extmarks) do
    local srow, scol = extmark.row, extmark.start_col
    extmark.row = nil
    extmark.start_col = nil
    api.nvim_buf_set_extmark(ctx.__outbuf, ns, srow, scol, {
      end_col = extmark.end_col,
      hl_group = extmark.hl_group,
    })
  end

  if win and api.nvim_win_is_valid(win) then
    api.nvim_win_set_buf(win, ctx.__outbuf)
  else
    win = api.nvim_open_win(ctx.__outbuf, false, { split = "below", win = -1, height = 15 })
  end
end)

local which = scheduled_append

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
    which(ctx, { { ret, "DiagnosticError" } })
  end
end

---@param ctx quicksys.ContextObj
---@param err any
---@param data any
M.default_handlers.stdout = function(ctx, err, data)
  if err then return vim.notify(err) end
  if data == nil then return end
  data = data:gsub("\r\n", "\n")
  local chunks = Parser(data):parse()
  if chunks == nil then chunks = {{ data }} end
  which(ctx, chunks)
end

---@param ctx quicksys.ContextObj
---@param err any
---@param data any
M.default_handlers.stderr = function(ctx, err, data)
  if err then return vim.notify(err) end
  if data == nil then return end
  data = data:gsub("\r\n", "\n")
  local chunks = Parser(data):parse()
  if chunks == nil then chunks = {{ data }} end
  which(ctx, chunks)

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
  local chunks = {}
  if ctx.__idx == 1 then
    local timestamp = os.date("%a %d %H:%M:%S", vim.uv.gettimeofday())
    local header = {
      { "System" },
      { "[", "@punctuation.bracket" },
      { "]", "@punctuation.bracket" },
      { " started at " },
      { timestamp, "Comment" },
    }
    vim.list_extend(chunks, header)
    for i = #ctx.__cmds, 1, -1 do
      local cmd = ctx.__cmds[i]
      table.insert(chunks, 3, { cmd[1], "Function" })
      if i > 1 then
        table.insert(chunks, 3, { " ➔ " })
      end
    end
    table.insert(chunks, { "\n" })
  end

  table.insert(chunks, { "\n" .. table.concat(ctx.__cmd, " ") .. "\n", "Comment" })

  which(ctx, chunks)
end

---@param ctx quicksys.ContextObj
---@param result vim.SystemCompleted
M.default_handlers.after = function(ctx, result)
  if ctx.__idx ~= #ctx.__cmds and result.code == 0 then
    return
  end
  local elapsed_s = (ctx.__end_time - ctx.__start_time) / 1e9
  local time_formatted = elapsed_s < 1 and ("%.2fms"):format(elapsed_s * 1000) or ("%.2fs"):format(elapsed_s)
  local chunks =  { { "\n" } }
  vim.list_extend(chunks, {
    result.code == 0 and { "finished ", "DiagnosticOk" } or { "exited ", "DiagnosticError" },
    { ("in %s with code " ):format(time_formatted) },
    { tostring(result.code), "Number" },
  })
  which(ctx, chunks)
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
