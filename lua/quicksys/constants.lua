local M = {}

M.SEVERITY_TO_CHAR = {
  error = "E",
  warning = "W",
  info = "I",
  note = "N",
  hint = "H",
}

M.CHAR_TO_SEVERITY = vim
  .iter(M.SEVERITY_TO_CHAR)
  :fold({}, function(acc, k, v)
    acc[v] = k
    return acc
  end)

return M
