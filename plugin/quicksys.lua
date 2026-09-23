
local CMD_OPTS = {
  target = { "quickfix", "loclist", "buf", "echo" },
  pos = { "left", "right", "top", "bot", "float" },
  cwd = true,
}

local parse_args = function(args)
  local opts = {}
  while true do
    local k, v, tail = args:match("^%s*(%w+)=(%S+)%s+(.*)$")
    if not (k and CMD_OPTS[k]) then break end
    opts[k] = v
    args = tail
  end
  return opts, args
end

vim.api.nvim_create_user_command("System", function(opts)
  local system_opts, args = parse_args(opts.args:gsub("%s+", " "))
  local cmds = vim
               .iter(vim.split(args, " && ", { trimempty = true }))
               :map(function(cmd) return vim.trim(cmd) end)
               :totable()
  require("quicksys.system").system_with(system_opts, unpack(cmds))
end, {
  desc = "TODO: system description",
  nargs = "+",
  complete = function(arglead)
    local candidates = {}
    local key = arglead:match("^(%w+)=")
    if key and CMD_OPTS[key] then
      for _, v in ipairs(CMD_OPTS[key]) do candidates[#candidates + 1] = key .. "=" .. v end
    else
      for k in pairs(CMD_OPTS) do candidates[#candidates + 1] = k .. "=" end
    end
    candidates = vim.tbl_filter(function(c) return c:find(arglead, 1, true) == 1 end, candidates)
    if #candidates > 0 then return candidates end
    return vim.fn.getcompletion(arglead, "shellcmdline")
  end
})

local function create_terminal_hls()
  for i, color in ipairs {
    "QuicksysBlack",
    "QuicksysRed",
    "QuicksysGreen",
    "QuicksysYellow",
    "QuicksysBlue",
    "QuicksysMagenta",
    "QuicksysCyan",
    "QuicksysWhite",
    "QuicksysBrightBlack",
    "QuicksysBrightRed",
    "QuicksysBrightGreen",
    "QuicksysBrightYellow",
    "QuicksysBrightBlue",
    "QuicksysBrightMagenta",
    "QuicksysBrightCyan",
    "QuicksysBrightWhite",
  } do
    local fg = vim.g["terminal_color_" .. (i - 1)]
    local ctermfg
    if fg == nil then ctermfg = i - 1 end
    vim.api.nvim_set_hl(0, color, { fg = fg, ctermfg = ctermfg, default = true })
  end
end
create_terminal_hls()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("quicksys-set-hls", {}),
  callback = function()
    create_terminal_hls()
  end,
})

-- local group = vim.api.nvim_create_augroup("quicksys.nvim", {})
-- vim.api.nvim_create_autocmd("FileType", {
--   desc = "replace native quickfix list",
--   pattern = "qf",
--   group = group,
--   callback = function(_)
--     local qflist = vim.fn.getqflist( { title = true, context = true, items = true })
--     local ctx = qflist.context
--     if ctx.source then return end
--     ctx = type(ctx) == "string" and {} or ctx
--     ctx.__source = qflist.title
--     vim.schedule(function()
--       local data = qflist.items
--       vim._with({ noautocmd = true }, function()
--         require("quicksys.quickfix").replace(ctx, data)
--       end)
--     end)
--   end
-- })
--
-- vim.api.nvim_create_autocmd("QuickFixCmdPost", {
--   group = group,
--   callback = function(_)
--     local qflist = vim.fn.getqflist( { title = true, context = true, items = true, qfbufnr = true })
--     local ctx = qflist.context
--     ctx = type(ctx) == "string" and {} or ctx
--     local ns = vim.api.nvim_create_namespace("quicksys-qftf")
--     local buf = qflist.qfbufnr
--     vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
--     vim.schedule(function()
--       local data = qflist.items
--       vim._with({ noautocmd = true }, function()
--         require("quicksys.quickfix").replace(ctx, data)
--       end)
--     end)
--   end
-- )
