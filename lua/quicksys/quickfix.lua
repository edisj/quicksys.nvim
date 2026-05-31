local fn = vim.fn
local api = vim.api

local config = require("quicksys.config")

local M = {}

--- This function exists because you need to be very careful with how
--- you "create" a quickfix buffer. If one naively creates a scratch buffer
--- and sets its filetype to "qf" and buftype to "quickfix", neovim treats
--- it as a "Location List" that is window local, meaning a subsequent call to
--- :copen will create a NEW buffer that acts as the global "real" quickfix buffer.
--- The problem with there is that all the facilities that populate the quickfix
--- and even vim.fn.setqflist() will interact with the buffer neovim created, where I
--- want my window to be attached to the REAL quickfix. Therefore, I do a hacky thing
--- where if a quickfix buffer doesn't exist, "create" one by calling :copen,
--- capture the bufnr, then immediately :cclose.
--- Now, the buffer associated with my `Window` interface will always be bound
--- to the actual vim quickfix buffer, so its contents will react to vim.fn.setqflist()
---
--- @return integer buf
local function _find_or_create_qf_buffer()
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if vim.bo[buf].filetype == "qf" and api.nvim_buf_get_name(buf):match("^[Quickfix List]$") then
      return buf
    end
  end

  -- NOTE: i wrap this with noautocmd because, if i don't,
  -- doing something like :copen before a quickfix buffer exists
  -- will trigger FileType autocmds which leads to duplicate windows
  local buf
  vim._with({ noautocmd = true }, function()
    vim.cmd("copen")
    buf = api.nvim_get_current_buf()
    vim.cmd("cclose")
  end)

  return buf
end

local _win = nil
local function win()
  if _win then return _win end

  local qf_config = config.windows.quickfix
  local win_opts = qf_config.win_opts
  win_opts.bufnr = _find_or_create_qf_buffer
  local kind = qf_config.kind
  _win = require("win")[kind](win_opts)
  return _win
end

function M.is_qf_open()
  return fn.getqflist({ winid = 0 }).winid ~= 0
end

function M.length()
  return #fn.getqflist()
end

function M.open(override_opts)
  if win():is_open() then return end
  local idx = math.max(vim.fn.getqflist({ idx = 0 }).idx, 1)
  return win()
    :open(override_opts)
    :set_cursor(idx, 0)
    .winid
end

function M.close()
  return win():is_open() and win():close() or M.is_qf_open() and vim.cmd.cclose()
end

function M.toggle(override_opts)
  return M.is_qf_open() and M.close() or M.open(override_opts)
end

function M.smart_toggle(override_opts)
  if win():is_focused() then
    M.close()
  elseif M.win():is_open() then
    win():focus()
  else
    M.open(override_opts)
  end
end

function M.next(opts)
  if M.length() == 0 then return end
  local idx = fn.getqflist({ idx = 0 }).idx
  if M.length() == idx then
    vim.cmd.clast()
  else
    vim.cmd.cnext()
  end
  if opts.on_select then opts.on_select() end
end

function M.prev(opts)
  if M.length() == 0 then return end
  local idx = fn.getqflist({ idx = 0 }).idx
  if idx == 1 then
    return vim.cmd.cfirst()
  end
  pcall(vim.cmd.cprev)
end

local function _setqflist(ctx, data, action)
  local source = require("quicksys").sources[ctx.__source]
  local handler = source.handler
  local items = handler(data)
  -- if #(items or {}) == 0 then return end
  local qftf = source.qftf
  -- IMPORTANT: if I don't wrap this with noautocmd, editor goes into
  -- infinite recursive hell of resetting the quickfix list...
  -- should investigate with debugger
  vim._with({ noautocmd = true }, function()
    fn.setqflist({}, action, {
      items = items,
      context = ctx,
      quickfixtextfunc = qftf,
    })
  end)
end
function M.set(ctx, data)     _setqflist(ctx, data, " ") end
function M.append(ctx, data)  _setqflist(ctx, data, "a") end
function M.replace(ctx, data) _setqflist(ctx, data, "r") end
function M.update(ctx, data)  _setqflist(ctx, data, "u") end

return M
