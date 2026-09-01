vim.api.nvim_create_user_command("System", function(args)
    local split_on_delim = vim.split((args.args:gsub(" && ", ";")), ";", { trimempty = true })
    local cmds = vim
      .iter(split_on_delim)
      :map(function(cmd) return vim.trim(cmd) end)
      :totable()
    require("quicksys").system(unpack(cmds))
  end, { desc = "TODO: system description", nargs = "+", complete = "file" })

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
-- })
