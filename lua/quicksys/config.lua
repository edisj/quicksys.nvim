local default_config = {
  takeover_external_quickfix = true,

  sources = {
    -- default = nil,
  },

  windows = {
    -- opening output closes quickfix and opening quickfix closes output
    only_one_open_at_a_time = true,

    output = {
      enabled = true,
      -- "float" or "split"
      kind = "split",
      -- requires https://edisj/win.nvim dependency
      win_opts = {
        enter = false, -- whether to enter the window when opening
        split = "below", -- "top" | "left" | "right" | "below"
        position = "bot",
        relative = "editor",
        style = "minimal",
        height = 10,
        -- width = 0.95,
        title = " OUTPUT ",
        keymaps = {
          { "n", "q", function(self) self:close() end },
        },
        -- vim.bo options
        bo = {
          modifiable = false,
        },
        -- vim.wo options
        wo = {
          scrolloff = 0,
          winhl = "Normal:NormalSplit,LineNr:Normal",
        },
      }
    },

    quickfix = {
      enabled = true,
      kind = "split",
      win_opts = {
        relative = "editor",
        position = "bot",
        style = "minimal",
        split = "below",
        height = 10,
        enter = true,
        -- bufnr = _find_or_create_qf_buffer,
        keymaps = {
          { "n", "q", function(self) self:close() end },
        },
        title = function()
          local text = vim.fn.getqflist({ title = true }).title
          return text == "" and " quickfix " or (" %s "):format(vim.trim(text))
        end,
        title_pos = "left",
        -- vim.wo options
        wo = {
          winfixbuf = true,
          cursorline = false,
          number = false,
          scrolloff = 2,
        },
      }
    }
  }
}

local M = {}

local function warn(msg)
end

local _did_setup = false
function M.setup(opts)
  _did_setup = true

  local merged_config = vim.tbl_deep_extend("force", default_config, opts or {})
  if
    (merged_config.windows.output.enabled or merged_config.windows.quickfix.enabled)
    and not M.has_win_dependency()
  then
    warn("missing win.nvim dependency. disabling windows features")
    merged_config.windows.output.enabled = false
    merged_config.windows.quickfix.enabled = false
  end

  for k, v in pairs(merged_config) do
    M[k] = v
  end

  return merged_config
end

function M.has_win_dependency()

end

setmetatable(M, {
  __index = function(t, k)
    if not _did_setup then
      M.setup()
    end
    return rawget(t, k)
  end
})

return M
