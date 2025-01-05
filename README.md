# `present.nvim`

Hey, this is a plugin for presenting markfdown files!. Build by [Teej](https://github.com/tjdevries) on Advent of Neovim 2024.

# Installation

```lua
return {
  'crisecheverria/present.nvim',
  config = function()
    -- Register the PresentStart command
    vim.api.nvim_create_user_command('PresentStart', function()
      require('present').start_presentation {}
    end, {})
  end,
}
```

# Usage

Execute command `:PresentStart`

Use `n` and `p` to navigate markdown files
