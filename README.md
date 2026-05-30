# Quicksys = vim.system + quickfix
**quicksys.nvim** is a bundled: 
- pretty output window
- pretty quickfix list
- (also pretty?) command runner

It aims to enhance the "edit -> compile -> edit" workflow and allow you to control exactly how the quickfix list is populated and formatted on a case-by-case basis.

TODO: image here

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
