# `present.nvim`

Hey, this is a plugin for presenting markdown files!. Built by [Teej](https://github.com/tjdevries) on Advent of Neovim 2024.

# Installation

## Using vim.pack.add() (Neovim v0.10+)

The simplest way to install this plugin is using Neovim's built-in package manager:

```lua
-- Install the plugin
vim.pack.add('https://github.com/crisecheverria/present.nvim')

-- The plugin will automatically load and register the :PresentStart command
```

## Using a Plugin Manager

```lua
return {
  'crisecheverria/present.nvim',
  config = function()
    -- No configuration needed - PresentStart command is automatically registered
    -- Optional: You can call setup if you want to customize anything in the future
    require('present').setup()
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

Which results to:

```lua
slides = {
    { title = "# This is the first slide", body = { "This is the content of the slide" } },
    { title = "# A second slide", body = { "This is more content" } },
},

```

## Starting a Presentation

1. Open a markdown file in Neovim
2. Execute the command `:PresentStart`
3. Navigate through slides using:
   - `n` - Next slide
   - `p` - Previous slide
   - `q` - Quit presentation

## Features

- **Clean, minimal interface**: Borderless slide content with only a title border
- **Responsive design**: Automatically adjusts to terminal size with proper margins
- **Markdown rendering**: Full markdown syntax highlighting for slide content
- **Simple navigation**: Intuitive keyboard shortcuts for presentation control
- **Auto-loading**: No configuration required - just install and use
