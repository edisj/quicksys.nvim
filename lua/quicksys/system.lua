local api = vim.api
local fn = vim.fn
local uv = vim.uv
local fs = vim.fs
local AnsiParser = require("quicksys.ansi_parser")

local M = { default_handlers = {} }
local targets = {}

---@param ... quicksys.Command | quicksys.Command[] | quicksys.CommandSpec
M.system = function(...)
  if select("#", ...) == 0 then return end
  return M._system({}, ...)
end

---@param opts table
---@param ... quicksys.Command | quicksys.Command[] | quicksys.CommandSpec
M.system_with = function(opts, ...)
  if select("#", ...) == 0 then return end
  local ctx = vim.tbl_deep_extend("force", {}, opts)
  return M._system(ctx, ...)
end

local last_cmd

local input = function(opts, last)
  local input_opts = {
    prompt = "System: ",
    scope = "project",
    completion = "customlist,v:lua.require'quicksys.completion'.customlist",
    default = last and last_cmd or nil,
  }
  local on_confirm = function(input)
    vim.cmd("echohl None")
    if input then
      M.system_with(opts, input)
      last_cmd = input
    end
  end
  vim.cmd("echohl Question")
  vim.ui.input(input_opts, on_confirm)
end

M.input = function(opts)
  input(opts)
end

M.input_last = function(opts)
  input(opts, true)
end

---@param ctx quicksys.ContextObj
---@param ... quicksys.Command | quicksys.Command[] | quicksys.CommandSpec
function M._system(ctx, ...)
  if ctx.__target == nil then ctx.__target = ctx.target or "quickfix" end
  if ctx.__target == "loclist" and not ctx.__loclist_parent then
    -- local curwin = api.nvim_get_current_win()
    -- ctx.__loclist_parent = fn.getloclist(0, { winid = true }).winid == curwin and curwin
    ctx.__loclist_parent = api.nvim_get_current_win()
  end

  ctx.__cwd = ctx.cwd or ctx.__cwd or fn.getcwd()

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
    ctx.__end_time = uv.hrtime()
    ctx.__end_times = ctx.__end_times or {}
    ctx.__end_times[#ctx.__end_times + 1] = ctx.__end_time

    handlers.exit(ctx, result)
    handlers.after(ctx, result)
    if #rest_of_args > 0 and result.code == 0 then
      M._system(ctx, unpack(rest_of_args))
    end
  end

  ctx.__start_time = ctx.__start_time or uv.hrtime()
  ctx.__start_times = ctx.__start_times or {}
  ctx.__start_times[#ctx.__start_times + 1] = ctx.__start_time
  local ok, ret = pcall(vim.system, cmd, {
    cwd = ctx.__cwd,
    text = true,
    stdout = function(...) handlers.stdout(ctx, ...) end,
    stderr = function(...) handlers.stderr(ctx, ...) end,
  }, on_exit)
  if ok then
    ctx.__system_objs[ctx.__idx] = ret
    return ctx
  else
    targets[ctx.__target](ctx, { { ret, "DiagnosticError" } })
  end
end


-- [default handlers] ---------------------------------------------------------

---@param ctx quicksys.ContextObj
---@param err any
---@param data any
local send_data_to_target = function(ctx, err, data)
  if err then return vim.notify(err) end
  if data == nil then return end
  data = data:gsub("\r\n", "\n")
  local chunks = AnsiParser(data):parse()
  if chunks == nil then chunks = {{ data }} end
  targets[ctx.__target](ctx, chunks)
end

M.default_handlers.stdout = send_data_to_target

M.default_handlers.stderr = send_data_to_target

---@param ctx quicksys.ContextObj
---@param result vim.SystemCompleted
---@diagnostic disable-next-line: unused-local
M.default_handlers.exit = function(ctx, result)
  -- NOTE: no-op
end

---@param ctx quicksys.ContextObj
M.default_handlers.before = function(ctx)
  local chunks = {}
  if ctx.__idx == 1 then
    local timestamp = os.date("%a %d %H:%M:%S", uv.gettimeofday())
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

  local cmd = type(ctx.__cmd) == "table" and (ctx.__cmd.cmd or ctx.__cmd) or ctx.__cmd
  table.insert(chunks, { "\n" .. table.concat(cmd, " ") .. "\n", "Comment" })

  targets[ctx.__target](ctx, chunks)
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
  targets[ctx.__target](ctx, chunks)
end


-- [targets] ------------------------------------------------------------------

local chunks_to_lines = function(chunks, start)
  local lines, extmarks = {}, {}
  local start_col = 0
  local offset = start or 0
  local i = 1
  local add_extmark = function(scol, ecol, hl)
    extmarks[#extmarks + 1] = {
      row = i - 1 + offset,
      start_col = scol,
      end_col = ecol,
      hl_group = hl,
    }
  end

  for _, chunk in ipairs(chunks) do
    local text, hl = chunk[1], chunk[2]
    local lines_in_chunk = vim.split(text, "\n")
    -- local lines_in_chunk = text == "\n" and { "" } or vim.split(text, "\n")
    local text_before_newline = lines_in_chunk[1]
    lines[i] = (lines[i] or "") .. text_before_newline
    if hl ~= nil then add_extmark(start_col, start_col + #text_before_newline, hl) end
    start_col = start_col + #text_before_newline
    for j = 2, #lines_in_chunk do
      i = i + 1
      start_col = 0
      local line = lines_in_chunk[j]
      lines[i] = (lines[i] or "") .. line
      if hl ~= nil then add_extmark(start_col, start_col + #line, hl) end
      start_col = start_col + #line
    end
  end

  return lines, extmarks
end

local ns = api.nvim_create_namespace("")
local send_chunks_to_list = function(list, ctx, chunks)
  local lines, extmarks = chunks_to_lines(chunks)

  local old_items = ctx.__items or {}
  local should_append_previous_items = #old_items > 1
  local extmark_offset = should_append_previous_items and #old_items - 1 or 0
  ctx.__extmarks = ctx.__extmarks or {}
  for _, m in ipairs(extmarks) do
    m.row = m.row + extmark_offset
    ctx.__extmarks[#ctx.__extmarks + 1] = m
  end

  ctx.__qf_predicate = ctx.qf_predicate
                       or ctx.__qf_predicate
                       or function(item) return item.filename ~= nil end
  local item_maybe_set_location = function(item)
    for filename, lnum, col in item.text:gmatch("([^%s:]+):(%d+):?(%d*)") do
      local path = filename:sub(1,1) == "/" and filename or fs.joinpath(ctx.__cwd, filename)
      local stat = uv.fs_stat(path)
      if lnum and stat and stat.type == "file" then
        item.filename = path
        item.lnum = tonumber(lnum)
        item.col = col ~= "" and tonumber(col) or 0
        break
      end
    end
    item.valid = ctx.__qf_predicate(item)
    return item
  end

  local new_items = vim
    .iter(lines)
    :map(function(line)
      if should_append_previous_items then
        local last_item = old_items[#old_items]
        last_item.text = last_item.text .. line
        if not last_item.valid then item_maybe_set_location(last_item) end
        should_append_previous_items = false
      else
        local item = { text = line }
        item_maybe_set_location(item)
        return item
      end
    end)
    :totable()

  vim.list_extend(old_items, new_items)
  ctx.__items = old_items

  local what = {
    items = ctx.__items,
    context = { __start_time = ctx.__start_time },
    quickfixtextfunc = function(info)
      local qfbufnr
      if info.quickfix == 1 then
        qfbufnr = fn.getqflist({ id = info.id, qfbufnr = 1 }).qfbufnr
      else
        qfbufnr = fn.getloclist(info.winid, { id = info.id, qfbufnr = 1 }).qfbufnr
      end

      local _lines = vim
        .iter(ctx.__items)
        :map(function(item) return (item.text ~= "" and item.text) or " " end)
        :totable()

      vim.schedule(function()
        api.nvim_buf_call(qfbufnr, function() vim.cmd("syntax clear") end)
        api.nvim_buf_clear_namespace(qfbufnr, ns, 0, -1)
        for _, m in ipairs(ctx.__extmarks) do
          api.nvim_buf_set_extmark(qfbufnr, ns, m.row, m.start_col, {
            end_col = m.end_col, hl_group = m.hl_group,
          })
        end
      end)

      return _lines
    end,
  }

  local context = list == "loclist" and fn.getloclist(ctx.__loclist_parent, { context = true }).context
                                     or fn.getqflist({ context = true }).context
  -- NOTE: using __start_time as a unique id to tell if
  -- current quickfix/loclist is the result of current context
  local current_list_from_this_cmd =
    type(context) == "table" and context.__start_time == ctx.__start_time
  local action = current_list_from_this_cmd and "u" or " "
  if list == "loclist" then
    fn.setloclist(0, {}, action, what)
  else
    fn.setqflist({}, action, what)
  end
end

local get_win_config = function(ctx)
  local pos = ctx.pos or ctx.__pos or "bot"
  if pos == "bot" or pos == "top" then
    local target = ctx.__target
    local split = ({ bot = "below", top = "above" })[pos]
    local max_height = math.floor(0.5 * vim.o.lines)
    local height
    if target == "loclist" or target == "quickfix" then
      height = math.min(max_height, #ctx.__items)
    else
      assert(target == "buf")
      height = math.min(max_height, api.nvim_buf_line_count(ctx.__target_buf))
    end
    return { split = split, win = -1, height = height }
  elseif pos == "right" or pos == "left" then
    local width = math.floor(0.5 * vim.o.columns)
    return { split = pos, win = -1, width = width}
  else
    assert(pos == "float")
    local width = math.floor(0.75 * vim.o.columns)
    local height = math.floor(0.75 * vim.o.lines)
    local row = math.floor(0.5 * ( vim.o.lines - height ))
    local col = math.floor(0.5 * ( vim.o.columns - width ))
    return { relative = "editor", row = row, col = col, width = width, height = height }
  end
end

targets.quickfix = vim.schedule_wrap(function(ctx, chunks)
  send_chunks_to_list("quickfix", ctx, chunks)

  if not ctx.__quickfix_bufnr then
    local qfbufnr = fn.getqflist({ qfbufnr = true }).qfbufnr
    if qfbufnr == 0 then
      vim._with({ noautocmd = true }, function()
        vim.cmd.copen()
        vim.cmd.close()
      end)
    end
    ctx.__quickfix_bufnr = fn.getqflist({ qfbufnr = true }).qfbufnr
  end

  local winid
  if api.nvim_win_is_valid(ctx.__quickfix_winid or -1) then
    winid = ctx.__quickfix_winid
  else
    winid = fn.getqflist({ winid = true }).winid
  end
  if winid == 0 then
    vim.cmd("silent copen")
    vim.cmd("wincmd p")
    winid = fn.getqflist({ winid = true }).winid
  end
  ctx.__quickfix_winid = winid
  vim.wo[ctx.__quickfix_winid].statusline = ""
  -- if not ctx.__quicfix_bufnr then ctx.__quickfix_bufnr = fn.getqflist({ qfbufnr = true }).qfbufnr end
  api.nvim_win_set_config(ctx.__quickfix_winid, get_win_config(ctx))
end)

targets.loclist = vim.schedule_wrap(function(ctx, chunks)
  send_chunks_to_list("loclist", ctx, chunks)

  if not ctx.__loclist_bufnr then
    local qfbufnr = fn.getloclist(ctx.__loclist_parent, { qfbufnr = true }).qfbufnr
    if qfbufnr == 0 then
      vim._with({ noautocmd = true, win = ctx.__loclist_parent }, function()
        vim.cmd.lopen()
        vim.cmd.lclose()
      end)
    end
    ctx.__loclist_bufnr = fn.getloclist(ctx.__loclist_parent, { qfbufnr = true }).qfbufnr
  end

  local winid
  if api.nvim_win_is_valid(ctx.__loclist_winid or -1) then
    winid = ctx.__loclist_winid
  else
    winid = fn.getloclist(ctx.__loclist_parent, { winid = true }).winid
  end
  if winid == 0 then
    vim._with({ noautocmd = true, win = ctx.__loclist_parent }, vim.cmd.lopen)
    -- api.nvim_win_call(ctx.__loclist_parent, vim.cmd.lopen)
    -- vim.cmd("lopen")
    -- vim.cmd("wincmd p")
    winid = fn.getloclist(ctx.__loclist_parent, { winid = true }).winid
  end
  ctx.__loclist_winid = winid
  vim.wo[ctx.__loclist_winid].statusline = ""
  -- if not ctx.__loclist_bufnr then ctx.__loclist_bufnr = fn.getloclist(ctx.__loclist_parent, { qfbufnr = true }).qfbufnr end
  api.nvim_win_set_config(ctx.__loclist_winid, get_win_config(ctx))
end)

targets.buf = vim.schedule_wrap(function(ctx, chunks)
  if ctx.__lines == nil then ctx.__lines = {} end

  if not ctx.__target_buf then
    local buf
    for _, _win in ipairs(api.nvim_tabpage_list_wins(0)) do
      local _buf = api.nvim_win_get_buf(_win)
      if vim.bo[_buf].filetype == "system_output" then
        buf = _buf
        ctx.__target_win = _win
        break
      end
    end
    if not buf then
      buf = api.nvim_create_buf(false, true)
      api.nvim_buf_set_name(buf, "quicksys://" .. buf .. "/output")
      api.nvim_set_option_value("filetype", "system_output", { buf = buf, scope = "local" })
      api.nvim_set_option_value("buftype", "nowrite", { buf = buf, scope = "local" })
      api.nvim_set_option_value("bufhidden", "hide", { buf = buf, scope = "local" })
      api.nvim_set_option_value("modifiable", false, { buf = buf, scope = "local" })
    end
    ctx.__target_buf = buf
  end

  local base = (#ctx.__lines > 0) and (#ctx.__lines - 1) or 0
  local lines, extmarks = chunks_to_lines(chunks, base)

  local start
  if #ctx.__lines > 0 then
    ctx.__lines[#ctx.__lines] = ctx.__lines[#ctx.__lines] .. table.remove(lines, 1)
    start = #ctx.__lines - 1
  else
    start = 0
  end
  vim.list_extend(ctx.__lines, lines)
  vim.bo[ctx.__target_buf].modifiable = true
  api.nvim_buf_set_lines(ctx.__target_buf, start, -1, false,
                        vim.list_slice(ctx.__lines, start + 1))
  vim.bo[ctx.__target_buf].modifiable = false

  for _, extmark in ipairs(extmarks) do
    local srow, scol = extmark.row, extmark.start_col
    extmark.row = nil
    extmark.start_col = nil
    api.nvim_buf_set_extmark(ctx.__target_buf, ns, srow, scol, {
      end_col = extmark.end_col,
      hl_group = extmark.hl_group,
    })
  end

  if not (ctx.__target_win and api.nvim_win_is_valid(ctx.__target_win)) then
    ctx.__target_win = api.nvim_open_win(ctx.__target_buf, false, get_win_config(ctx))
  else
    api.nvim_win_set_config(ctx.__target_win, get_win_config(ctx))
  end
end)

targets.echo = vim.schedule_wrap(function(ctx, chunks)
  if ctx.__msgchunks == nil then ctx.__msgchunks = {} end
  vim.list_extend(ctx.__msgchunks, chunks)
  ctx.__msgid = vim.api.nvim_echo(ctx.__msgchunks, false, { id = ctx.__msgid })
end)

---@alias quicksys.Command string | string[]

---@class quicksys.CommandSpec
---@field cmd string[]
---@field stdout? fun()
---@field stderr? fun()
---@field exit? fun()
---@field before? fun()
---@field after? fun()

---@class quicksys.ContextObj
---@field __cmd? quicksys.Command current command being executed
---@field __cmds? quicksys.Command[] list of all commands to be executed
---@field __target? string
---@field __idx? integer index of current command in sequence
---@field __start_time? integer vim.uv.hrtime when first command was executed
---@field __start_times? integer[] start time for each command
---@field __end_time? integer vim.uv.hrtime when current command exited
---@field __end_times? integer[] end time for each command
---@field [any] any arbitrary user data to be passed through callbacks

return M
