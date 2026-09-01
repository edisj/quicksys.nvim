local M = {}

---
---@param ctx quicksys.ContextObj
---@param ... string
---@return vim.SystemObj?
function M.system(ctx, ...)
  return require("quicksys.system").system(ctx, ...)
end

---@param win_opts? table
function M.quickfix_open(win_opts)
  return require("quicksys.quickfix").open(win_opts)
end

---whether the quickfix list window is open
---@return boolean
function M.quickfix_is_open()
  return require("quicksys.quickfix").is_open()
end

---
---@param opts? table
function M.quickfix_next(opts)
  return require("quicksys.quickfix").next(opts)
end

---
---@param opts? table
function M.quickfix_prev(opts)
  return require("quicksys.quickfix").prev(opts)
end

return M
