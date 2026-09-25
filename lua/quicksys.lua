local M = {}

---
---@param ... string
function M.system(...)
  return require("quicksys.system").system(...)
end

function M.system_with(opts, ...)
  return require("quicksys.system").system_with(opts, ...)
end

function M.input(opts)
  require("quicksys.system").input(opts)
end

return M
