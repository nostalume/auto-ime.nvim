# auto-ime

A Neovim plugin that automatically switches your input method to Latin when leaving insert mode or command line mode.

## Motive

When editing code or writing text in Neovim, users often switch to their native language input method (e.g., Chinese, Japanese, Korean) while in insert mode. However, when exiting insert mode to normal mode or command mode, the input method often stays in the non-Latin state, requiring manual switching back to English. This is especially inconvenient when using Vim commands like `h`, `j`, `k`, `l` or other normal mode commands.

This plugin solves this problem by automatically switching your input method back to Latin/English whenever you leave insert mode or command line mode.

### Prerequisites

- **Neovim** 0.9.0 or later
- **Operating System**: Windows, WSL, Linux, or macOS
- **Platform-specific requirements**:
  - **Windows**: **Nothing**
  - **WSL**: Windows interop enabled and `powershell.exe` available (on `PATH` or at the default `/mnt/c/Windows/System32/WindowsPowerShell/v1.0/` path). For a Linux-native IME in WSLg, `fcitx5-remote` or `ibus` is used if PowerShell is unavailable or fails.
  - **Linux**: `fcitx5-remote` or `ibus` must be installed and executable
  - **macOS**: `macism` must be installed (available via Homebrew: `brew install macism`)

## Installation

### Using [vim.pack](https://neovim.io/doc/user/pack/) (Neovim 0.12+)

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
  event = "VeryLazy",
  config = function()
    require("auto-ime").setup()
  end,
}
```

## Configuration

The plugin works out of the box with default settings. Currently, no additional configuration options are available.

## Supported Platforms

| Platform | Input Method Tools Supported                                  |
| -------- | ------------------------------------------------------------- |
| Windows  | Native IME API                                                |
| WSL      | Windows PowerShell via interop; fcitx5-remote or ibus fallback |
| Linux    | fcitx5-remote, ibus                                           |
| macOS    | macism                                                        |

## How It Works

1. When Neovim starts, the plugin detects your operating system
2. It registers autocommands for `InsertLeave` and `CmdlineLeave` events
3. When you exit insert mode or command line mode, the plugin automatically calls the appropriate system API or command to switch your input method back to Latin/English

On Windows, each exit uses the current foreground window's IME handle. If no handle is available, the switch is skipped rather than sent to an older window.

On WSL, setup starts one background PowerShell process. An exit before it is ready is not replayed later, so a delayed command cannot change the IME after you have moved to another window. If the worker fails, the plugin uses a Linux IME tool when available. Otherwise, it warns once. If no switching tool is installed, it warns on the first attempted switch.

## Contributing

### Local Development

```lua
{
  dir = "~/path/to/dev/auto-ime.nvim",
  event = "VeryLazy",
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

### Checks

From the repository root, run:

```sh
nvim --headless -u NONE -i NONE -l tests/run.lua
stylua --check lua plugin tests
```

On Windows, set `AUTO_IME_TEST_POWERSHELL=1` before the Neovim command to also check that the persistent PowerShell worker starts and accepts commands. This does not change the active IME.

## Thanks

[Alternative to im-select.exe on Windows](https://github.com/keaising/im-select.nvim/issues/20)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
