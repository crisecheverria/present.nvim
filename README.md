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

The way it works it's by parsing markdown file creating a list of slides with title and body, searching for the `#` sign to create slides and the rest is the body.

```markdown
# This is the first slide

This is the content of the slide

# A second slide

This is more content
```

```lua
slides = {
    { title = "# This is the first slide", body = { "This is the content" } },
    { title = "# A second slide", body = { "This is more content" } },
},

```

Execute the presentation with command `:PresentStart`

Use `n` and `p` to navigate markdown files
