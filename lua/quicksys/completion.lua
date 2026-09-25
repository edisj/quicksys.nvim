local M = {}


local cache = {}

-- M.customlist = function(arglead, cmdline, cursorpos)
--   return {
--     { word = arglead, abbr = "arglead: " .. arglead, info = "INFO?" },
--     { word = cmdline, abbr = "cmdline: ".. cmdline, info = "INFO?" },
--     { word = tostring(cursorpos), abbr = "CURSOR POS: " .. tostring(cursorpos), info = "INFO?" },
--   }
-- end

    local function merge(cmdline, abbr)
      for k = math.min(#cmdline, #abbr), 1, -1 do
        if cmdline:sub(-k) == abbr:sub(1, k) then
          return cmdline:sub(1, #cmdline - k) .. abbr
        end
      end
      return cmdline .. abbr
    end

M.customlist = function(arglead, cmdline, cursorpos)
  -- vim.api.nvim_win_close(require("vim._core.ui2").wins.dialog, true)
  if cache[cmdline] then return cache[cmdline] end

  -- local quoted_arglead = ('\"%s\"'):format(arglead)
  local cmd = {
    "fish",
    "-c",
    "complete -C " .. vim.fn.shellescape(cmdline),
  }
  -- vim.system(cmd, function(result)
  --   if result.code ~= 0 then return end
  --   local items = vim.split(result.stdout, "\n")
  --   local candidates = {}
  --   for _, item in ipairs(items) do
  --     local abbr, menu = unpack(vim.split(item, "\t"))
  --     if abbr and abbr ~= "" then
  --       candidates[#candidates + 1 ] = { word = merge(cmdline, abbr), abbr = abbr, menu = menu }
  --     end
  --   end
  --   cache[cmdline] = candidates
  -- end)

  local result = vim.system(cmd):wait()
    if result.code ~= 0 then return end
    local items = vim.split(result.stdout, "\n")
    local candidates = {}
    for _, item in ipairs(items) do
      local abbr, menu = unpack(vim.split(item, "\t"))
      if abbr and abbr ~= "" then
        candidates[#candidates + 1 ] = { word = merge(cmdline, abbr), abbr = abbr, menu = menu }
      end
    end
    cache[cmdline] = candidates
  return candidates

end

return M
