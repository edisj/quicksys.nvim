
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
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].filetype == "qf" and vim.api.nvim_buf_get_name(buf):match("^[Quickfix List]$") then
      return buf
    end
  end

  -- NOTE: i wrap this with noautocmd because, if i don't,
  -- doing something like :copen before a quickfix buffer exists
  -- will trigger FileType autocmds which leads to duplicate windows
  local buf
  vim._with({ noautocmd = true }, function()
    vim.cmd("copen")
    buf = vim.api.nvim_get_current_buf()
    vim.cmd("cclose")
  end)

  return buf
end

function M.is_open()
  return vim.fn.getqflist({ winid = 0 }).winid ~= 0
end

local function idx()
  return math.max(vim.fn.getqflist({ idx = 0 }).idx, 1)
end

local function len()
  return #vim.fn.getqflist()
end

function M.next(opts)
  if len() == 0 then return end
  if len() == idx() then
    vim.cmd.clast()
  else
    vim.cmd.cnext()
  end
end

function M.prev(opts)
  if len() == 0 then return end
  if idx() == 1 then
    return vim.cmd.cfirst()
  end
  pcall(vim.cmd.cprev)
end

---@param ctx quicksys.ContextObj
---@param data any
---@param action " " | "a" | "r" | "u"
local function _setqflist(ctx, data, action)
  ctx.__source = ctx.source or ctx.__source or ctx.__cmd and ctx.__cmd[1]
  local source = require("quicksys").sources[ctx.__source]
  local handler = source.handler
  local items = handler(data)
  local qftf = source.qftf
  local qf_title = vim.fn.getqflist{title=true}.title
  -- IMPORTANT: if I don't wrap this with noautocmd, editor goes into
  -- infinite recursive hell of resetting the quickfix list...
  -- should investigate with debugger
  vim._with({ noautocmd = true }, function()
    vim.fn.setqflist({}, action, {
      items = items,
      context = ctx,
      title = qf_title == ":setqflist()" and tostring(source.name) or qf_title,
      quickfixtextfunc = qftf,
    })
  end)
end
function M.set(ctx, data)     _setqflist(ctx, data, " ") end
function M.append(ctx, data)  _setqflist(ctx, data, "a") end
function M.replace(ctx, data) _setqflist(ctx, data, "r") end
function M.update(ctx, data)  _setqflist(ctx, data, "u") end

return M
