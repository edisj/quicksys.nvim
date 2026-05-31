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

local function _create_autocmds(config)
  local group = vim.api.nvim_create_augroup("quicksys-group", {})

  if config.windows.quickfix.enabled then
    vim.api.nvim_create_autocmd("BufRead", {
      group = group,
      callback = function(ev)
        if vim.bo[ev.buf].buftype ~= "quickfix" then
          return
        end
        vim.schedule(function()
          vim.cmd.cclose()
          require("quicksys.quickfix").open()
        end)
      end
    })
  end

  if config.takeover_external_quickfix then
    vim.api.nvim_create_autocmd("FileType", {
      desc = "replace native quickfix list",
      pattern = "qf",
      group = group,
      callback = function(_)
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
      end
    })

    vim.api.nvim_create_autocmd("QuickFixCmdPost", {
      group = group,
      callback = function(_)
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
end

function M.setup(opts)

  opts = opts or {}
  local config = require("quicksys.config").setup(opts)

  _create_autocmds(config)

  vim.api.nvim_create_user_command("System", function(args)
    local cmds = vim
      .iter(vim.split(args.args, ";"))
      :map(function(cmd) return vim.trim(cmd) end)
      :totable()
    require("quicksys").system({}, unpack(cmds))
  end, { desc = "TODO: system description", nargs = "+", complete = "shellcmd" })
end

setmetatable(M, {
  __index = function(_, k)
    return require("quicksys.api")[k]
  end,
})

return M
