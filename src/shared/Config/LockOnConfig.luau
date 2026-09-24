--!strict
-- Lock-on (D-115): which opponent a lock takes, and when it lets go. Pure data; the camera's side of it
-- is FeelConfig.LockOn, and tests/LockOn.spec.luau ties these numbers to the ones they answer to.

local LockOnConfig = {
	-- Studs from the local character within which a lock is taken: as far as the longest glyph reaches,
	-- so anything a lock can take is something a glyph can hit.
	AcquireStuds = 90,
	-- And past which it lets go: the distance beyond which other bodies are no longer posed
	-- (PostureConfig.RangeStuds), so a locked target is never drawn stiff. Wider than AcquireStuds, so a
	-- target stepping back and forth across the edge is not dropped and retaken.
	BreakStuds = 140,
	-- Degrees either side of the camera's aim a target must be within: you lock what you look at.
	ConeDegrees = 40,
	-- Closer than this across the floor, the character is not turned: the direction to the target is noise.
	FacingMinStuds = 0.5,
	-- The mark over a locked target: its size in pixels, and how far above the top of its body it floats.
	Marker = { SizePx = 26, LiftStuds = 1.4 },
}

return LockOnConfig
