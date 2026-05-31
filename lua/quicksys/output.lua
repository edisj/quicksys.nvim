local config = require("quicksys.config")

local M = {}

local _win_stub = {
  open = function() end,
  close = function() end,
  is_open = function() end,
  toggle = function() end,
}

local _win
function M.win(ctx)
  -- if not has_neowin() then return end
  if _win then return _win end

  local win_opts = config.windows.output.win_opts
  win_opts.bufnr = function(_)
    local bufnr = vim.api.nvim_create_buf(false, true)
    if ctx then vim.api.nvim_buf_set_name(bufnr, table.concat(ctx.__cmd, " ")) end
    return bufnr
  end

  local kind = config.windows.output.kind
  _win = require("win")[kind](win_opts)
  return _win
end

function M.open(win_opts)   return M.win():open(win_opts).winid end
function M.close()          M.win():close() end
function M.is_open()        return M.win():is_open() end
function M.toggle(win_opts) return not M.is_open() and M.open(win_opts) or M.close() end

return M
