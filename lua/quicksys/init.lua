local M = {}

---@type table<string, QuickFixSource>
M.sources = setmetatable({}, {
  __index = function(t, _)
    return t.default
  end
})

M.sources.default = {
  name = "default",
  handler = function(data) return data end,
  qftf = function(_) return {} end,
}

function M.setup(opts)

  local group = vim.api.nvim_create_augroup("quickfix-group", {})

  vim.api.nvim_create_autocmd("BufRead", {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].buftype ~= "quickfix" or require("quicksys.quickfix").win():is_open() then
        return
      end
      vim.schedule(function()
        vim.cmd.cclose()
        require("quicksys.quickfix").open()
      end)
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "qf",
    group = group,
    desc = "replace native quickfix",
    callback = function()
      local qflist = vim.fn.getqflist( { title = true, context = true, items = true })
      local ctx = qflist.context
      if ctx.source then return end
      ctx = type(ctx) == "string" and {} or ctx
      ctx.__source = qflist.title
      vim.schedule(function()
        local data = qflist.items
        vim._with({ noautocmd = true }, function()
          require("quicksys.quickfix").replace(ctx, data)
        end)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("QuickFixCmdPost", {
    group = group,
    callback = function(ev)
      local qflist = vim.fn.getqflist( { title = true, context = true, items = true, qfbufnr = true })
      local ctx = qflist.context
      ctx = type(ctx) == "string" and {} or ctx
      local ns = vim.api.nvim_create_namespace("quicksys-qftf")
      local buf = qflist.qfbufnr
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      vim.schedule(function()
        local data = qflist.items
        vim._with({ noautocmd = true }, function()
          require("quicksys.quickfix").replace(ctx, data)
        end)
      end)

    end
  })

end

return M
