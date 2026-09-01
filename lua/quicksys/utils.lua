local constants = require("quicksys.constants")

local M = {}

---@return boolean
function M.has_win_dependency()
  local ok, _ = pcall(require, "win")
  return ok
end

function M.warn(msg)
  local chunks = {
    { "[" },
    { "WARN", "DiagnosticWarn" },
    { "] quicksys.nvim: "},
    { msg },
  }
  vim.api.nvim_echo(chunks, true, {})
end

local function _gen_qftf(format_line, decorate_line)
  return function(info)
    local qflist = info.quickfix == 1 and vim.fn.getqflist({ all = true })
    local items = qflist.items
    local lines = vim
      .iter(items)
      :map(function(item) return format_line(item) end)
      :totable()

    local set_extmarks = function(buf)
      local ns = vim.api.nvim_create_namespace("quicksys.quickfix")
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      vim.api.nvim_buf_call(buf, function() vim.cmd("syntax clear") end)
      for i = 1, #lines do
        local item = items[i]
        local line = lines[i]
        local extmark = function(_opts) vim.api.nvim_buf_set_extmark(buf, ns, i-1, 0, _opts) end
        decorate_line(item, line, extmark)
      end
    end
    vim.schedule(function() set_extmarks(qflist.qfbufnr) end)

    return lines
  end
end

---@param opts? table
---@return fun(info: QuickFixTextFuncInfo): string[]
function M.gen_nested_qftf(opts)
  opts = opts or {}

  local format_line = opts.format_line or function(item)
    return item.valid == 1 and vim.trim(item.text) or vim.fn.fnamemodify(item.text, ":~:.")
  end

  local decorate_line = opts.decorate_line or function(item, line, extmark)
    if not item.user_data.header or item.valid == 1 then
      extmark({ virt_text = { { "    "} }, virt_text_pos = "inline", })
      extmark({
        virt_text = { { ("[%s, %s]"):format(item.lnum, item.col), "Comment" } },
        virt_text_pos = "eol",
        hl_mode = "combine",
      })
    else
      -- extmark({ hl_group = "qfFileName", end_col = #line })
    end
  end

  return _gen_qftf(format_line, decorate_line)
end

function M.gen_flat_qftf(opts)
  opts = opts or {}

  local format_line = opts.format_line or function(item)
    return vim.trim(item.text)
  end

  local decorate_line = opts.decorate_line or function(item, line, extmark)
    local icon, hl
    icon = config.icons[item.type] or ""
    if icon == "" then
      local file = vim.api.nvim_buf_get_name(item.bufnr)
      icon, hl = require("mini.icons").get("extension", vim.fn.fnamemodify(file, ":e"))
    else
      hl = constants.QF_TYPE_TO_HL[item.type]
    end
    extmark({ virt_text = { { " " .. icon .. " ", hl } }, virt_text_pos = "inline", })
    local bufname = vim.api.nvim_buf_get_name(item.bufnr)
    local filename = vim.fn.fnamemodify(bufname, ":p:~")
    extmark({
      virt_text = { { ("%s:%s:%s"):format(filename, item.lnum, item.col), "Comment" } },
      virt_text_pos = "eol",
      hl_mode = "combine",
    })
  end

  return _gen_qftf(format_line, decorate_line)
end

return M
