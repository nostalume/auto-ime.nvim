# auto-ime

A Neovim plugin that automatically switches your input method to Latin when leaving insert mode or command line mode.

## Motive

When editing code or writing text in Neovim, users often switch to their native language input method (e.g., Chinese, Japanese, Korean) while in insert mode. However, when exiting insert mode to normal mode or command mode, the input method often stays in the non-Latin state, requiring manual switching back to English. This is especially inconvenient when using Vim commands like `h`, `j`, `k`, `l` or other normal mode commands.

This plugin solves this problem by automatically switching your input method back to Latin/English whenever you leave insert mode or command line mode.

### Prerequisites

- **Neovim** 0.9.0 or later
- **Operating System**: Windows, WSL, Linux, or macOS
- **Platform-specific requirements**:
  - **Windows & WSL**: **Nothing**
  - **Linux**: `fcitx5-remote` or `ibus` must be installed and executable
  - **macOS**: `macism` must be installed (available via Homebrew: `brew install macism`)

## Installation

### Using [nvim.pack](https://github.com/nvim-pack/nvim-pack)

Add to your `init.lua`.

```lua
vim.pack.add({
  { src = "https://github.com/lvyuemeng/auto-ime.nvim" },
})

require("auto-ime").setup()
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'lvyuemeng/auto-ime.nvim'
```

Then add to your `init.lua`.

```lua
require("auto-ime").setup()
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "lvyuemeng/auto-ime.nvim",
  config = function()
    require("auto-ime").setup()
  end
}
```

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "lvyuemeng/auto-ime.nvim",
  event = "VeryLazy", -- it only takes < 1ms
  config = function()
    require("auto-ime").setup()
  end,
}
```

## Configuration

The plugin works out of the box with default settings. Currently, no additional configuration options are available.

## Supported Platforms

| Platform | Input Method Tools Supported |
| -------- | ---------------------------- |
| Windows  | Native IME API               |
| WSL      | Native (Built-in PowerShell) |
| Linux    | fcitx5-remote, ibus          |
| macOS    | macism                       |

## How It Works

1. When Neovim starts, the plugin detects your operating system
2. It registers autocommands for `InsertLeave` and `CmdlineLeave` events
3. When you exit insert mode or command line mode, the plugin automatically calls the appropriate system API or command to switch your input method back to Latin/English

## Contributing

### Local Development

```lua
{
  dir = "~/path/to/dev/auto-ime.nvim",
  event = "VeryLazy", -- it only takes < 1ms
  config = function()
    require("auto-ime").setup()
  end,
}
```

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

Please ensure your code follows the project's coding style and includes appropriate documentation.

## Thanks

[Alternative to im-select.exe on Windows](https://github.com/keaising/im-select.nvim/issues/20)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
