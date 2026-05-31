local quickfix = require("quicksys.quickfix")
local output = require("quicksys.output").win

local M = {}

---@param ctx quicksys.ContextObj
---@param err any
---@param data any
local function default_stdout(ctx, err, data)
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

---@param ctx quicksys.ContextObj
---@param err any
---@param data any
local function default_stderr(ctx, err, data)
  if err then return vim.print(err) end
  if data == nil then return end
  data = data:gsub("\n$", "") -- remove annoying trailing newline
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
    -- otherwise create a new quickfix list for this context
    quickfix.close()
    quickfix.set(ctx, data)
  end)
end

---@param ctx quicksys.ContextObj
---@param result vim.SystemCompleted
local function default_exit(ctx, result)
  -- do nothing
end

local print_intro_message = vim.schedule_wrap(function(ctx)
  local timestamp = os.date("%a %d %H:%M:%S", vim.uv.gettimeofday())
  local chunks = {
    "System",
    { "[", "@punctuation.bracket" },
    { "]", "@punctuation.bracket" },
    " started at ",
    { timestamp, "Comment" },
  }
  for i = #ctx.__cmds, 1, -1 do
    local cmd = ctx.__cmds[i]
    table.insert(chunks, 3, { cmd[1], "StatuslineNormal" })
    if i > 1 then
      table.insert(chunks, 3, " ➔ ")
    end
  end
  output()
    :open()
    :set_lines({}, { force = true })
    :append_lines({ chunks, "" }, true)
end)

---@param ctx quicksys.ContextObj
local function default_before(ctx)
  if ctx.__idx ~= 1 then return end
  print_intro_message(ctx)
end

local print_final_message = vim.schedule_wrap(function(ctx, result)
  local elapsed = (ctx.__end_time - ctx.__start_time) / 1e9
  local chunks = {
    { #ctx.__cmds > 1 and "[" or "", "@punctuation.bracket" },
    { #ctx.__cmds > 1 and "]" or "", "@punctuation.bracket" },
    result.code == 0 and { " finished ", "DiagnosticOk" } or { " exited ", "DiagnosticError" },
    { ("in %.3fs with code " ):format(elapsed) },
    { tostring(result.code), "Number" },
  }
  for i = #ctx.__cmds, 1, -1 do
    local cmd = ctx.__cmds[i]
    if result.code == 0 then
      table.insert(chunks, 2, { cmd[1], "StatuslineNormal" })
      if i > 1 then
        table.insert(chunks, 2, { " ✔ ", "DiagnosticOk" })
      end
    else
      local is_before_error = i <= ctx.__idx
      local is_after_error = i > ctx.__idx + 1
      table.insert(chunks, 2, { cmd[1], is_before_error and "StatuslineNormal" or "Comment"})
      if i > 1 then
        table.insert(chunks, 2, {
          is_after_error and " ➔ " or is_before_error and " ✔ " or " ✘ ",
          is_after_error and "Comment" or is_before_error and "DiagnosticOk" or "DiagnosticError"
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

---@param ctx quicksys.ContextObj
---@param result vim.SystemCompleted
local function default_after(ctx, result)
  if ctx.__idx ~= #ctx.__cmds and result.code == 0 then
    return
  end
  print_final_message(ctx, result)
end

M.default_handlers = {
  stdout = default_stdout,
  stderr = default_stderr,
  exit = default_exit,
  before = default_before,
  after = default_after,
}

---@param ctx quicksys.ContextObj
---@param ... quicksys.Command | quicksys.Command[] | quicksys.CommandSpec
---@return vim.SystemObj?
function M.system(ctx, ...)
  if select("#", ...) == 0 then return end

  ctx = ctx or {}
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
    ctx.__idx = 0
    ctx.__cmds = vim
      .iter({...})
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
      M.system(ctx, unpack(rest_of_args))
    end
  end

  local ctx_wrap = function(fn)
    return function(...) fn(ctx, ...) end
  end

  ctx.__start_time = ctx.__start_time or vim.uv.hrtime()
  ctx.__start_times = ctx.__start_times or {}
  ctx.__start_times[#ctx.__start_times + 1] = ctx.__start_time
  return vim.system(cmd, {
    text = true,
    stdout = ctx_wrap(handlers.stdout),
    stderr = ctx_wrap(handlers.stderr),
  }, on_exit)
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
