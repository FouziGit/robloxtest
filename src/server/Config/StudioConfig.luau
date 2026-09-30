--!strict
-- What a Studio session may write into the experience's live data. With Enable Studio Access to API Services
-- on (docs/STUDIO_SETUP.md §2), a server started in Studio reads and writes the very DataStores the public
-- servers use, so each switch below is off unless a test needs it, and goes back off after that test.
--
-- Lives under src/server, like DeveloperConfig: no client reads it. Pure on purpose: no Roblox global and no
-- require, so the tests load it by path.

local StudioConfig = {}

-- A Studio test purchase, of a pass or a product, still goes through Roblox's test dialog, and is then logged,
-- acknowledged and granted nothing (MonetizationService/Sandbox, D-211): everything a purchase grants is
-- written into the profile, and ProfileStore saves the profile Studio holds, which is the player's real one.
-- On, the purchase is granted and saved exactly as a live server does it; a pass bought that way leaves the
-- cache at the next join, since Roblox never sold it.
StudioConfig.PersistTestPurchases = false

-- Ratings earned in a Studio session stay off the season ladders (LeaderboardService, D-210). On, a positive
-- user id -- the developer's own account playing solo -- is written as a live server writes it. The local
-- players of Test → Clients and Servers have non-positive ids and are never written, whatever this says.
StudioConfig.WriteLadders = false

return StudioConfig
