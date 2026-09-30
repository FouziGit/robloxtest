--!strict
-- What a Studio session may write into the experience's live data. With Enable Studio Access to API Services
-- on (docs/STUDIO_SETUP.md §2), a server started in Studio reads and writes the very DataStores the public
-- servers use, so each switch below is off unless a test needs it, and goes back off after that test.
--
-- Lives under src/server, like DeveloperConfig: no client reads it. Pure on purpose: no Roblox global and no
-- require, so the tests load it by path.

local StudioConfig = {}

-- Ratings earned in a Studio session stay off the season ladders (LeaderboardService, D-203). On, a positive
-- user id -- the developer's own account playing solo -- is written as a live server writes it. The local
-- players of Test → Clients and Servers have non-positive ids and are never written, whatever this says.
StudioConfig.WriteLadders = false

return StudioConfig
