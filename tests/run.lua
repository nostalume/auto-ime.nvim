local expected_version = os.getenv("AUTO_IME_EXPECT_NVIM")
if expected_version then
  local version = vim.version()
  local actual = string.format("%d.%d.%d", version.major, version.minor, version.patch)
  assert(actual == expected_version, "expected Neovim " .. expected_version .. ", got " .. actual)
end

dofile("tests/platforms.lua")
dofile("tests/setup.lua")
