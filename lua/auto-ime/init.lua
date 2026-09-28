local M = {}

local core = require("auto-ime.core")

function M.setup(opts)
  core.setup(opts or {})
end

return M
