return {
  name = "nested",
  handler = function(data)
    local grouped_by_file = {}
    for _, item in ipairs(data) do
      if item.valid == 1 then
        local filename = vim.api.nvim_buf_get_name(item.bufnr)
        grouped_by_file[filename] = grouped_by_file[filename] or {}
        table.insert(grouped_by_file[filename], item)
      end
    end

    local list = {}
    for filename, group in pairs(grouped_by_file) do
      table.insert(list, {
        user_data = { header = true },
        text = filename,
        valid = 0,
      })
      for _, item in ipairs(group) do
        table.insert(list, item)
      end
    end

    return list
  end,
  qftf = require("quicksys.utils").gen_nested_qftf()
}
