--!strict
local Harness = require("./harness")
local MatchmakingCore = require("../src/shared/Pure/MatchmakingCore")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local config = { BaseWindow = 100, WindowGrowthPerSecond = 15, MaxWindow = 800, MaxQueueSeconds = 240 }

local function entry(userId: number, rating: number, joinedAt: number)
	return { UserId = userId, Rating = rating, JoinedAt = joinedAt }
end

describe("MatchmakingCore", function()
	it("enqueues once and dequeues", function()
		local queue = MatchmakingCore.newQueue("Duel1v1")
		expect(MatchmakingCore.enqueue(queue, entry(1, 1000, 0))).toBe(true)
		expect(MatchmakingCore.enqueue(queue, entry(1, 1000, 0))).toBe(false)
		expect(MatchmakingCore.size(queue)).toBe(1)
		expect(MatchmakingCore.contains(queue, 1)).toBe(true)
		expect(MatchmakingCore.dequeue(queue, 1)).toBe(true)
		expect(MatchmakingCore.dequeue(queue, 1)).toBe(false)
		expect(MatchmakingCore.size(queue)).toBe(0)
	end)

	it("pairs players inside the base window and not outside", function()
		local queue = MatchmakingCore.newQueue("Duel1v1")
		MatchmakingCore.enqueue(queue, entry(1, 1000, 0))
		MatchmakingCore.enqueue(queue, entry(2, 1080, 0))
		MatchmakingCore.enqueue(queue, entry(3, 1500, 0))
		local matches = MatchmakingCore.findMatches(queue, 1, 2, 0, config)
		expect(matches).toHaveLength(1)
		expect(matches[1].Teams).toEqual({ { 2 }, { 1 } })
		expect(matches[1].AverageRating).toBe(1040)
		expect(MatchmakingCore.size(queue)).toBe(1)
		expect(MatchmakingCore.contains(queue, 3)).toBe(true)
	end)

	it("widens the window while waiting", function()
		local queue = MatchmakingCore.newQueue("Duel1v1")
		MatchmakingCore.enqueue(queue, entry(1, 1000, 0))
		MatchmakingCore.enqueue(queue, entry(2, 1400, 0))
		expect(MatchmakingCore.findMatches(queue, 1, 2, 5, config)).toHaveLength(0)
		expect(MatchmakingCore.window(entry(1, 1000, 0), 20, config)).toBe(400)
		expect(MatchmakingCore.findMatches(queue, 1, 2, 20, config)).toHaveLength(1)
		expect(MatchmakingCore.window(entry(1, 1000, 0), 1000, config)).toBe(config.MaxWindow)
	end)

	it("prefers the closest rating for the longest-waiting anchor", function()
		local queue = MatchmakingCore.newQueue("Duel1v1")
		MatchmakingCore.enqueue(queue, entry(10, 1000, 0))
		MatchmakingCore.enqueue(queue, entry(11, 1090, 3))
		MatchmakingCore.enqueue(queue, entry(12, 1010, 5))
		local matches = MatchmakingCore.findMatches(queue, 1, 2, 6, config)
		expect(matches).toHaveLength(1)
		expect(matches[1].Teams).toEqual({ { 12 }, { 10 } })
	end)

	it("forms balanced 3v3 teams", function()
		local queue = MatchmakingCore.newQueue("Team3v3")
		local ratings = { 1500, 1400, 1300, 1200, 1100, 1000 }
		for index, rating in ipairs(ratings) do
			MatchmakingCore.enqueue(queue, entry(index, rating, 0))
		end
		local matches = MatchmakingCore.findMatches(queue, 3, 2, 100, config)
		expect(matches).toHaveLength(1)
		local teams = matches[1].Teams
		expect(teams).toHaveLength(2)
		expect(teams[1]).toHaveLength(3)
		expect(teams[2]).toHaveLength(3)
		local function sum(ids: { number }): number
			local total = 0
			for _, id in ipairs(ids) do
				total += ratings[id]
			end
			return total
		end
		expect(math.abs(sum(teams[1]) - sum(teams[2]))).toBeLessThanOrEqual(100)
		expect(MatchmakingCore.size(queue)).toBe(0)
	end)

	it("does not form a match with too few players", function()
		local queue = MatchmakingCore.newQueue("Team3v3")
		for index = 1, 5 do
			MatchmakingCore.enqueue(queue, entry(index, 1000, 0))
		end
		expect(MatchmakingCore.findMatches(queue, 3, 2, 0, config)).toHaveLength(0)
		expect(MatchmakingCore.size(queue)).toBe(5)
	end)

	it("expires players that waited too long", function()
		local queue = MatchmakingCore.newQueue("Duel1v1")
		MatchmakingCore.enqueue(queue, entry(1, 1000, 0))
		MatchmakingCore.enqueue(queue, entry(2, 1000, 200))
		expect(MatchmakingCore.expire(queue, 241, config)).toEqual({ 1 })
		expect(MatchmakingCore.size(queue)).toBe(1)
		expect(MatchmakingCore.contains(queue, 2)).toBe(true)
	end)

	it("forms several matches in one pass and is deterministic", function()
		local queue = MatchmakingCore.newQueue("Duel1v1")
		for index = 1, 6 do
			MatchmakingCore.enqueue(queue, entry(index, 1000 + index * 10, index))
		end
		local matches = MatchmakingCore.findMatches(queue, 1, 2, 10, config)
		expect(matches).toHaveLength(3)
		expect(MatchmakingCore.size(queue)).toBe(0)
		local ids = {}
		for _, match in ipairs(matches) do
			for _, team in ipairs(match.Teams) do
				for _, id in ipairs(team) do
					table.insert(ids, id)
				end
			end
		end
		table.sort(ids)
		expect(ids).toEqual({ 1, 2, 3, 4, 5, 6 })
	end)
end)

-- The quick duel for newcomers (E10-S7): held to MatchConfig.Newcomer.MaxWindow for their first WindowSeconds.
describe("MatchmakingCore and newcomers", function()
	local MatchConfig = require("../src/shared/Config/MatchConfig")
	local NEWCOMER = MatchConfig.Newcomer
	local live = {
		BaseWindow = MatchConfig.Matchmaking.BaseWindow,
		WindowGrowthPerSecond = MatchConfig.Matchmaking.WindowGrowthPerSecond,
		MaxWindow = MatchConfig.Matchmaking.MaxWindow,
		MaxQueueSeconds = MatchConfig.Matchmaking.MaxQueueSeconds,
		NewcomerMaxWindow = NEWCOMER.MaxWindow,
		NewcomerSeconds = NEWCOMER.WindowSeconds,
	}

	local function newcomer(userId: number, rating: number, joinedAt: number)
		return { UserId = userId, Rating = rating, JoinedAt = joinedAt, Newcomer = true }
	end

	it("are the story's numbers: 300 at most, for 120 seconds", function()
		expect(NEWCOMER.MaxWindow).toBe(300)
		expect(NEWCOMER.WindowSeconds).toBe(120)
		expect(NEWCOMER.MinMatches).toBe(5)
		expect(NEWCOMER.MinLevel).toBe(10)
	end)

	it("stops a newcomer's window at the cap until the seconds are over", function()
		expect(MatchmakingCore.window(newcomer(1, 1000, 0), 60, live)).toBe(300)
		expect(MatchmakingCore.window(entry(1, 1000, 0), 60, live)).toBe(800)
		expect(MatchmakingCore.window(newcomer(1, 1000, 0), 119, live)).toBe(300)
		expect(MatchmakingCore.window(newcomer(1, 1000, 0), 120, live)).toBe(800)
		expect(MatchmakingCore.cap(newcomer(1, 1000, 0), 60, live)).toBe(300)
		expect(MatchmakingCore.cap(entry(1, 1000, 0), 60, live)).toBe(math.huge)
		-- A queue with no newcomer rule is the queue it always was.
		expect(MatchmakingCore.window(newcomer(1, 1000, 0), 60, config)).toBe(800)
	end)

	it("keeps a veteran's wide window from reaching a newcomer, until the newcomer has waited long enough", function()
		local queue = MatchmakingCore.newQueue("Duel1v1")
		MatchmakingCore.enqueue(queue, entry(1, 1700, 0))
		MatchmakingCore.enqueue(queue, newcomer(2, 1000, 50))
		expect(MatchmakingCore.findMatches(queue, 1, 2, 100, live)).toHaveLength(0)
		expect(MatchmakingCore.findMatches(queue, 1, 2, 169, live)).toHaveLength(0)
		expect(MatchmakingCore.findMatches(queue, 1, 2, 170, live)).toHaveLength(1)
	end)

	it("keeps every member of a 3v3 within a newcomer's cap, not only the anchor", function()
		local queue = MatchmakingCore.newQueue("Team3v3")
		-- The anchor waited longest. Nearest it, 1050, a newcomer at 1100 and 1150; then 710, well inside the anchor's
		-- window but 390 from the newcomer, and 1310 and 1320, further from the anchor but near enough the newcomer.
		MatchmakingCore.enqueue(queue, entry(1, 1000, 0))
		MatchmakingCore.enqueue(queue, entry(2, 1050, 10))
		MatchmakingCore.enqueue(queue, newcomer(3, 1100, 90))
		MatchmakingCore.enqueue(queue, entry(4, 1150, 10))
		MatchmakingCore.enqueue(queue, entry(5, 710, 10))
		MatchmakingCore.enqueue(queue, entry(6, 1310, 10))
		MatchmakingCore.enqueue(queue, entry(7, 1320, 10))
		local matches = MatchmakingCore.findMatches(queue, 3, 2, 100, live)
		expect(matches).toHaveLength(1)
		local members: { number } = {}
		for _, team in ipairs(matches[1].Teams) do
			for _, id in ipairs(team) do
				table.insert(members, id)
			end
		end
		table.sort(members)
		-- 710 is left in the queue for a later scan; the newcomer plays with the two further up instead.
		expect(members).toEqual({ 1, 2, 3, 4, 6, 7 })
		expect(MatchmakingCore.contains(queue, 5)).toBe(true)
	end)

	it("never pairs a newcomer more than 400 from anybody before 120 seconds, whatever the queue (spec)", function()
		-- A fixed pseudo-random stream, so the case is the same on every run.
		local seed = 12345
		local function random(low: number, high: number): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return low + seed % (high - low + 1)
		end
		local formed = 0
		for _ = 1, 300 do
			local teamSize = if random(0, 1) == 0 then 1 else 3
			local queue = MatchmakingCore.newQueue("Mode")
			local joined: { [number]: { Rating: number, JoinedAt: number, Newcomer: boolean } } = {}
			for id = 1, random(2, 12) do
				local item = { Rating = random(400, 2000), JoinedAt = random(0, 110), Newcomer = random(0, 2) == 0 }
				joined[id] = item
				MatchmakingCore.enqueue(
					queue,
					{ UserId = id, Rating = item.Rating, JoinedAt = item.JoinedAt, Newcomer = item.Newcomer }
				)
			end
			-- The service scans every two seconds.
			for now = 0, 118, 2 do
				for _, match in ipairs(MatchmakingCore.findMatches(queue, teamSize, 2, now, live)) do
					formed += 1
					local ids: { number } = {}
					for _, team in ipairs(match.Teams) do
						for _, id in ipairs(team) do
							table.insert(ids, id)
						end
					end
					for _, id in ipairs(ids) do
						local player = joined[id]
						if player.Newcomer and now - player.JoinedAt < NEWCOMER.WindowSeconds then
							for _, other in ipairs(ids) do
								expect(math.abs(joined[other].Rating - player.Rating)).toBeLessThanOrEqual(400)
								expect(math.abs(joined[other].Rating - player.Rating)).toBeLessThanOrEqual(
									NEWCOMER.MaxWindow
								)
							end
						end
					end
				end
			end
		end
		-- The stream forms matches; a case that paired nobody would prove nothing.
		expect(formed).toBeGreaterThan(100)
	end)
end)
