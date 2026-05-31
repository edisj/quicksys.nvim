local M = {}

---
---@param opts? table
function M.output_open(opts) require("quicksys.output").open(opts) end

---@return boolean
function M.output_is_open() return require("quicksys.output").is_open() end

---
function M.output_close() require("quicksys.output").close() end

---
function M.output_focus() require("quicksys.output").focus() end

---
function M.output_toggle() return require("quicksys.output").toggle() end

---
function M.output_smart_toggle() require("quicksys.output").smart_toggle() end

---
---@param win_opts? table
function M.quickfix_open(win_opts) return require("quicksys.quickfix").open(win_opts) end

---whether the quickfix list window is open
---@return boolean
function M.quickfix_is_open() return require("quicksys.quickfix").is_qf_open() end

---
function M.quickfix_close() return require("quicksys.quickfix").close() end

---
function M.quickfix_focus() return require("quicksys.quickfix").focus() end

---toggle
---@param win_opts? table
function M.quickfix_toggle(win_opts) return require("quicksys.quickfix").toggle(win_opts) end

---smart toggle
function M.quickfix_smart_toggle() return require("quicksys.quickfix").smart_toggle() end

---
---@param opts? table
function M.quickfix_next(opts) return require("quicksys.quickfix").next(opts) end

---
---@param opts? table
function M.quickfix_prev(opts) return require("quicksys.quickfix").prev(opts) end

---
---@param ctx table
---@param data any
function M.quickfix_set(ctx, data) require("quicksys.quickfix").set(ctx, data) end

---
---@param ctx table
---@param data any
function M.quickfix_append(ctx, data) require("quicksys.quickfix").append(ctx, data) end

---
---@param ctx table
---@param data any
function M.quickfix_replace(ctx, data) require("quicksys.quickfix").replace(ctx, data) end

---
---@param ctx table
---@param data any
function M.quickfix_update(ctx, data) require("quicksys.quickfix").update(ctx, data) end

---
---@param ctx table
---@param ... string
---@return vim.SystemObj?
function M.system(ctx, ...) return require("quicksys.system").system(ctx, ...) end

---
---@return table
function M.get_builtin_sources() return vim.deep_copy(require("quicksys.builtin.sources")) end

return M
