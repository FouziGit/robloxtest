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
