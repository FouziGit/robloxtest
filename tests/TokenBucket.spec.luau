--!strict
local Harness = require("./harness")
local TokenBucket = require("../src/shared/Util/TokenBucket")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

describe("TokenBucket", function()
	it("starts full and drains", function()
		local bucket = TokenBucket.new(3, 1, 0)
		expect(TokenBucket.tryTake(bucket, 0)).toBe(true)
		expect(TokenBucket.tryTake(bucket, 0)).toBe(true)
		expect(TokenBucket.tryTake(bucket, 0)).toBe(true)
		expect(TokenBucket.tryTake(bucket, 0)).toBe(false)
	end)

	it("refills over time up to capacity", function()
		local bucket = TokenBucket.new(2, 2, 0)
		expect(TokenBucket.tryTake(bucket, 0, 2)).toBe(true)
		expect(TokenBucket.tryTake(bucket, 0.25)).toBe(false)
		expect(TokenBucket.tryTake(bucket, 0.5)).toBe(true)
		expect(TokenBucket.available(bucket, 100)).toBe(2)
	end)

	it("supports weighted costs", function()
		local bucket = TokenBucket.new(5, 0, 0)
		expect(TokenBucket.tryTake(bucket, 0, 4)).toBe(true)
		expect(TokenBucket.tryTake(bucket, 0, 2)).toBe(false)
		expect(TokenBucket.tryTake(bucket, 0, 1)).toBe(true)
	end)

	it("ignores clock going backwards", function()
		local bucket = TokenBucket.new(1, 1, 10)
		expect(TokenBucket.tryTake(bucket, 10)).toBe(true)
		expect(TokenBucket.tryTake(bucket, 5)).toBe(false)
	end)
end)
