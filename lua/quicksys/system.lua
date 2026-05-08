local fs = vim.fs
local fn = vim.fn
local uv = vim.uv
local api = vim.api

local quickfix = require("quicksys.quickfix")

local M = {}

local _stdout_win = nil
local function stdout_win()
  if _stdout_win then return _stdout_win end

  local winopts = {
    enter = false,
    style = "minimal",
    split = "below",
    height = 10,
    keymaps = {
      { "n", "q", function(self) self:close() end },
    },
    bo = {
      modifiable = false,
      bufhidden = "wipe",
    },
    wo = {
      scrolloff = 0,
      winhl = "Normal:NormalSplit",
    },
  }

  _stdout_win = Win.split(winopts)
  return _stdout_win
end

local function on_stdout(ctx, err, data)
  if err then return vim.print(err) end
  if data == nil then return end
  data = data:gsub("\n$", "") -- remove annoying trailing newline
  local lines = vim.split(data, "\n")
  vim.schedule(function()
    vim.cmd.cclose()
    stdout_win()
      :open({ bufnr = function(_)
        local bufnr = api.nvim_create_buf(false, true)
        api.nvim_buf_set_name(bufnr, table.concat(ctx.__cmd, " "))
        return bufnr
      end })
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
    -- current quickfix list is the result of current command
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
  local elapsed = (end_time - ctx.__start_time) / 1e9
  local chunks = {
    { tostring(ctx.__cmd[1]), "Function" },
    obj.code == 0 and { " finished ", "DiagnosticOk" } or { " exited ", "DiagnosticError" },
    { ("in %.3fs with code " ):format(elapsed) },
    { tostring(obj.code), "Number" },
  }
  vim.schedule(function() api.nvim_echo(chunks, true, {}) end)

  vim.schedule(function()
    local qf_context = fn.getqflist({ context = true }).context
    local current_quickfix_from_this_cmd = type(qf_context) == "table" and qf_context.__start_time == ctx.__start_time
    if not current_quickfix_from_this_cmd then return end
    qf_context.__end_time = end_time
    fn.setqflist({}, "r", { context = qf_context })
    if obj.code == 0 then
      quickfix.replace(ctx, "")
      quickfix.close()
    elseif obj.code ~= 0 and quickfix.length() > 0 then
      if _stdout_win then stdout_win():close() end
    end
  end)
end

M.default_handlers = {
  stdout = on_stdout,
  stderr = on_stderr,
  exit = on_exit,
}

function M.syscall(ctx, handlers, ...)
  if select("#", ...) == 0 then return end

  local cmd = select(1, ...)
  cmd = type(cmd) == "string" and vim.split(cmd, " ") or cmd
  ctx = ctx or {}
  ctx.__cmd = cmd

  handlers = vim.tbl_deep_extend("force", M.default_handlers, handlers or {})

  local ctx_wrap = function(f)
    return function(...) f(ctx, ...) end
  end

  local rest_of_args = { select(2, ...) }
  ---@diagnostic disable-next-line: redefined-local
  local on_exit
  if #rest_of_args > 0 then
    on_exit = function(obj)
      handlers.exit(ctx, obj)
      if obj.code == 0 then
        M.syscall(ctx, handlers, unpack(rest_of_args))
      end
    end
  else
    on_exit = ctx_wrap(handlers.exit)
  end

  vim.schedule(quickfix.close)
  ctx.__start_time = uv.hrtime()
  return vim.system(cmd, {
    text = true,
    stdout = ctx_wrap(handlers.stdout),
    stderr = ctx_wrap(handlers.stderr),
  }, on_exit)
end

return M
