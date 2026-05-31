local constants = require("quicksys.constants")
local type_to_hl = {
  E = "DiagnosticError",
  W = "DiagnosticWarn",
  I = "DiagnosticInfo",
  H = "DiagnosticHint",
  N = "DiagnosticHint",
}

return {
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
