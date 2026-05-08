local constants = require("quicksys.constants")
local type_to_hl = {
  E = "DiagnosticError",
  W = "DiagnosticWarn",
  I = "DiagnosticInfo",
  H = "DiagnosticHint",
  N = "DiagnosticHint",
}

local M = {}

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
M.sources = {}

M.sources.flat = {
  name = "flat",
  handler = function(data) return data end,
  qftf = function(info)
    local list = info.quickfix == 1 and vim.fn.getqflist({ all = true })
    local items = list.items

    local max_len = 0
    -- need to find longest fields for right/left justification
    for _, item in ipairs(items) do
      local full_name = vim.api.nvim_buf_get_name(item.bufnr)
      local rel_name = vim.fn.fnamemodify(full_name, ":~:.")
      local len = #rel_name + #tostring(item.lnum) + #tostring(item.col) + 2
      max_len = math.max(len, max_len)
    end

    local lines = vim
      .iter(ipairs(items))
      :map(function(_, item)
        local name = vim.api.nvim_buf_get_name(item.bufnr)
        local rel_name = vim.fn.fnamemodify(name, ":~:.")
        local pad_len = max_len - #rel_name - #tostring(item.lnum) - #tostring(item.col) - 2
        local pad = string.rep(" ", pad_len)
        return ("%s:%s:%s%s %s"):format(
          rel_name,
          item.lnum,
          item.col,
          pad,
          vim.trim(item.text)
        )
      end)
      :totable()

    local set_extmarks = vim.schedule_wrap(function(buf)
      local ns = vim.api.nvim_create_namespace("quicksys-qftf")
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      vim.api.nvim_buf_call(buf, function() vim.cmd("syntax clear") end)

      local extmark = function(i, col, opts) vim.api.nvim_buf_set_extmark(buf, ns, i-1, col, opts) end
      for i, item in ipairs(items) do
        local icon, hl
        icon = require("ui.icons").diagnostics[constants.CHAR_TO_SEVERITY[item.type]] or ""
        if icon == "" then
          local file = vim.api.nvim_buf_get_name(item.bufnr)
          icon, hl = require("mini.icons").get("extension", vim.fn.fnamemodify(file, ":e"))
        else
          hl = type_to_hl[item.type]
        end
        extmark(i, 0, {
          virt_text = { { icon .. " ", hl } },
          virt_text_pos = "inline",
        })
        local name = vim.api.nvim_buf_get_name(item.bufnr)
        local rel_name = vim.fn.fnamemodify(name, ":~:.")
        extmark(i, 0, { hl_group = "Keyword", end_col = #rel_name })
        extmark(i, #rel_name, { hl_group = "Number", end_col = #rel_name + #tostring(item.lnum) + #tostring(item.col) + 2 })
      end

    end)

    set_extmarks(list.qfbufnr)
    return lines
  end,
}

M.sources.nested = {
  name = "nested",
  handler = function(data)

    local grouped_by_file = {}
    for _, item in ipairs(data) do
      if item.valid == 1 then
        local filename = vim.api.nvim_buf_get_name(item.bufnr)
        grouped_by_file[filename] = grouped_by_file[filename] or {}
        table.insert(grouped_by_file[filename], item)
      end
    end

    local list = {}
    for filename, group in pairs(grouped_by_file) do
      table.insert(list, {
        user_data = { header = true },
        text = filename,
        valid = 0,
      })
      for _, item in ipairs(group) do
        table.insert(list, item)
      end
    end

    return list
  end,

  qftf = function(_)
    local qflist = vim.fn.getqflist({ all = true })
    local items = qflist.items
    local lines = vim
      .iter(ipairs(items))
      :map(function(_, item)
        return item.valid == 1 and vim.trim(item.text) or vim.fn.fnamemodify(item.text, ":~:.")
      end)
      :totable()

    local set_extmarks = vim.schedule_wrap(function(buf)
      local ns = vim.api.nvim_create_namespace("quicksys-qftf")
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      vim.api.nvim_buf_call(buf, function() vim.cmd("syntax clear") end)

      local extmark = function(i, opts) vim.api.nvim_buf_set_extmark(buf, ns, i-1, 0, opts) end
      for i = 1, #lines do
        local item = items[i]
        local line = lines[i]
        if item.valid == 1 then
          extmark(i, {
            virt_text = { { "    ", nil } },
            virt_text_pos = "inline",
          })
          local icon = require("ui.icons").diagnostics[constants.CHAR_TO_SEVERITY[item.type]] or ""
          local hl = type_to_hl[item.type]
          extmark(i, {
            virt_text = { { icon .. " ", hl } },
            virt_text_pos = "inline",
          })
          extmark(i, {
            virt_text = { { ("[%s, %s]"):format(item.lnum, item.col), "Comment" } },
            virt_text_pos = "eol",
          })
        else
          extmark(i, { hl_group = "qfFileName", end_col = #line })
        end
      end

    end)

    -- NOTE: this must be scheduled because the quickfix buffer text
    -- isn't set until this function returns
    set_extmarks(qflist.qfbufnr)

    return lines
  end,
}

return M
