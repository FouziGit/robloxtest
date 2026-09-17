--!strict
-- Token bucket rate limiter. Pure module (clock injected) so it is testable under Lune.

export type Bucket = {
	capacity: number,
	refillPerSecond: number,
	tokens: number,
	updatedAt: number,
}

local TokenBucket = {}

function TokenBucket.new(capacity: number, refillPerSecond: number, now: number): Bucket
	return {
		capacity = capacity,
		refillPerSecond = refillPerSecond,
		tokens = capacity,
		updatedAt = now,
	}
end

local function refill(bucket: Bucket, now: number)
	local elapsed = now - bucket.updatedAt
	if elapsed > 0 then
		bucket.tokens = math.min(bucket.capacity, bucket.tokens + elapsed * bucket.refillPerSecond)
		bucket.updatedAt = now
	end
end

-- Consumes `cost` tokens (default 1). Returns true if allowed.
function TokenBucket.tryTake(bucket: Bucket, now: number, cost: number?): boolean
	refill(bucket, now)
	local amount = cost or 1
	if bucket.tokens >= amount then
		bucket.tokens -= amount
		return true
	end
	return false
end

function TokenBucket.available(bucket: Bucket, now: number): number
	refill(bucket, now)
	return bucket.tokens
end

return TokenBucket
