---@class QuickFixTextFuncInfo
---@field id integer quickfix or locaiton list identifier
---@field quickfix 0|1 1 if called for quickfix, 0 if called for loclist
---@field winid integer 0 for quickfix, otherwise winid associated with loclist
---@field start_idx integer index of first entry for which text should be returned
---@field end_idx integer index of last entry for which text should be returned

---@class QuickFixSource
---@field name? string
---@field handler fun(data: any): vim.quickfix.entry[]
---@field qftf? fun(info: QuickFixTextFuncInfo): string[]

---@type table<string, QuickFixSource>
return setmetatable({}, {
  __index = function(_, k)
    local modname = "quicksys.builtin.sources." .. k
    local ok, mod = pcall(require, modname)
    if ok then return mod end
  end
})
