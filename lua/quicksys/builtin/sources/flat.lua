local constants = require("quicksys.constants")
local type_to_hl = {
  E = "DiagnosticError",
  W = "DiagnosticWarn",
  I = "DiagnosticInfo",
  H = "DiagnosticHint",
  N = "DiagnosticHint",
}

return {
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

      local extmark = function(i, col, opts)
        vim.api.nvim_buf_set_extmark(buf, ns, i-1, col, opts)
      end
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
