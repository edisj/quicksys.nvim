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
  qftf = require("quicksys.builtin.sources.flat").qftf
}
