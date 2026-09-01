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


M.QF_TYPE_TO_HL = {
  E = "DiagnosticError",
  W = "DiagnosticWarn",
  I = "DiagnosticInfo",
  H = "DiagnosticHint",
  N = "DiagnosticHint",
}

return M
