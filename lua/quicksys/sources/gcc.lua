local constants = require("quicksys.constants")

return {
  name = "gcc",
  handler = function(data)
    local lines = vim.split(data, "\n")
    local error_pattern = "^([^:]+):(%d+):(%d+): ([^:]+): (.+)$"
    local line_to_qf_item = function(line)
      local filename, lnum, col, severity, message = line:match(error_pattern)
      if filename == nil then return end
      return {
        filename = filename,
        lnum = lnum,
        col = col,
        text = message,
        type = constants.SEVERITY_TO_CHAR[severity],
      }
    end
    return vim
      .iter(lines)
      :map(line_to_qf_item)
      :totable()
  end,

  qftf = function(info)
    local list = info.quickfix == 1 and vim.fn.getqflist({ items = true })
    local items = list.items

    local name_pad = 0
    local lnum_max = 0
    local cnum_max = 0

    -- need to find longest fields for right/left justification
    for _, item in ipairs(items) do
      local full_name = vim.api.nvim_buf_get_name(item.bufnr)
      local rel_name = vim.fn.fnamemodify(full_name, ":.")
      name_pad = math.max(name_pad, #rel_name)
      lnum_max = math.max(lnum_max, #tostring(item.lnum))
      cnum_max = math.max(cnum_max, #tostring(item.col))
    end
    local filename_fmt = string.format("%%%ds", name_pad)

    local formatted_lines = {}
    for _, item in ipairs(items) do
      local full_name = vim.api.nvim_buf_get_name(item.bufnr)
      local rel_name = vim.fn.fnamemodify(full_name, ":.")
      local pad = string.rep(" ", lnum_max - #tostring(item.lnum) + cnum_max - #tostring(item.col))
      local formatted_line = (filename_fmt..":%d:%d: "..pad.."%s: %s"):format(
        rel_name,
        item.lnum,
        item.col,
        constants.CHAR_TO_SEVERITY[item.type],
        item.text
      )
      formatted_lines[#formatted_lines + 1] = formatted_line
    end

    return formatted_lines
  end,

  syntax = function()
    vim.cmd([[
      syntax clear
      syntax match qfFileName   /^[^:]\+/
      syntax match qfLineNr     /\zs\d\+\ze:\d\+/
      syntax match qfColNr      /\zs\d\+\ze: /
      syntax match qfError      /\<error\>/
      syntax match qfWarning    /\<warning\>/
      syntax match qfWarn       /\<warn\>/
      syntax match qfNote       /\<note\>/
      syntax match qfText       /[^:]\+$/ contains=qfError,qfWarning,qfNote
      syntax match qfSeparator1 /:/
    ]])
  end,
}
