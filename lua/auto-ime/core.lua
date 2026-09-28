local M = {}
local platform = require("auto-ime.platforms")

function M.setup(opts)

  local ensure_latin = platform.detect()

  if not ensure_latin then
    return
  end

  vim.api.nvim_create_autocmd({ "InsertLeave", "CmdlineLeave" }, {
    group = vim.api.nvim_create_augroup("ime_auto_switch", { clear = true }),
    callback = ensure_latin,
    desc = "Return IME to Latin",
  })
end

return M