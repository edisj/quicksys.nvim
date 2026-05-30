# Quicksys = vim.system + quickfix
A pretty output window, a pretty quickfix list, and a (also pretty?) command runner bundled together so that you can enhance the "edit -> compile -> edit" workflow, control exactly how the quickfix list is populated and formatted on a case-by-case basis, and much more...

TODO: image + description here


## Why?
what problem does it solve? motivate with intended workflow

## Installation
#### vim.pack (nvim 0.12+)
```lua
vim.pack.add({
    "https://github.com/edisj/neowin.nvim",
    "https://github.com/edisj/quicksys.nvim"
})
```
#### lazy.nvim
```lua
{
    "edisj/quicksys.nvim",
    opts = {},
    dependencies = { "edisj/neowin.nvim" },
}
```

## Quickstart
```lua
local quicksys = require("quicksys")
quicksys.setup()
builtin_sources = require("quicksys.builtin.sources")
quicksys.sources.Diagnostics = builtin_sources.nested
```

## Configuration
```lua
require("quicksys").setup({
    ...
})
```

## How it works

## Usage
