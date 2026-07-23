local source = debug.getinfo(1, "S").source
local file = source:sub(1, 1) == "@" and source:sub(2) or source
local root = file:match("^(.*)/[^/]+$") or "."

-- Enable the bundled `hs` command for health checks and assisted diagnostics.
require("hs.ipc")

package.path = table.concat({
  root .. "/?.lua",
  root .. "/?/init.lua",
  package.path,
}, ";")

local bootstrap = require("app.bootstrap")

if _G.AnimeExpeditionsMac and _G.AnimeExpeditionsMac.stop then
  _G.AnimeExpeditionsMac:stop("reload")
end

_G.AnimeExpeditionsMac = bootstrap.new({ root = root })
_G.AnimeExpeditionsMac:start()

return _G.AnimeExpeditionsMac
