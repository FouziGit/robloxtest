--!strict
-- The movement guard against a simulated client, network and server (tests/movementsim.luau), on the shipped
-- numbers. Every honest case is a thing the game really does to a body -- walking, jumps, dashes, every
-- knockback and lift, Caret, server teleports, falls from the boss arena, stalls, hitches, low frame rates,
-- ragdolls, shoves -- and must come out clean, or at worst corrected without a strike where the server
-- cannot tell it from a cheat. Every cheat case is an attack the guard was designed against and must be
-- corrected or struck.
local Harness = require("./harness")
local Sim = require("./movementsim")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function case(sc: Sim.Scenario, expected: Sim.Expectation)
	it(("%s: %s"):format(expected, sc.Name), function()
		local stats = Sim.run(sc)
		if not Sim.meets(stats, expected) then
			error(("expected %s, got %s"):format(expected, Sim.describe(stats)), 0)
		end
	end)
end

local function walk(speed: number): (number) -> number
	return function(): number
		return speed
	end
end

local ARENA = { { X0 = -100, X1 = 100, Top = 0, Tagged = true }, { X0 = -40, X1 = 40, Top = 500, Tagged = true } }
local BOSS_FALL = { { X0 = -80, X1 = 80, Top = 900, Tagged = true }, { X0 = -100, X1 = 200, Top = 0, Tagged = true } }
local COVER_WALL = { { X0 = 40, X1 = 42, Bottom = 0, Top = 6 } }
local T0 = 4.0

describe("MovementScenarios: honest, the draft's cases", function()
	for _, L in ipairs({ 0.05, 0.3, 0.5 }) do
		case({ Name = ("walk 10s, one-way %.2f"):format(L), Seconds = 10, Latency = L, Walk = walk(16) }, "clean")
	end
	for _, stall in ipairs({ 0.5, 1.2, 2, 3, 5, 8 }) do
		case({
			Name = ("walk + uplink stall %.1fs"):format(stall),
			Seconds = 14,
			Latency = 0.1,
			Walk = walk(16),
			Stalls = { { 2, 2 + stall } },
		}, "clean")
	end
	case({
		Name = "stand still 20s then walk",
		Seconds = 25,
		Latency = 0.1,
		Walk = function(t: number): number
			return if t > 20 then 16 else 0
		end,
	}, "clean")
	for _, L in ipairs({ 0.05, 0.3, 0.5 }) do
		for _, fps in ipairs({ 60, 15, 10 }) do
			case({
				Name = ("dash while walking, L=%.2f fps=%d"):format(L, fps),
				Seconds = 6,
				Latency = L,
				Fps = fps,
				Walk = walk(16),
				Grants = { { 2, "Dash", 100, 0, 0.22, 0.9 }, { 4.6, "Dash", 100, 0, 0.22, 0.9 } },
			}, "clean")
		end
	end
	for _, fps in ipairs({ 60, 30, 15, 10 }) do
		case({
			Name = ("juggle: finisher, Sweep, Rupture, boss Fury fps=%d"):format(fps),
			Seconds = 8,
			Latency = 0.15,
			Fps = fps,
			Grants = {
				{ 1.0, "Knockback", 45, 18, 0.25, 1.9 },
				{ 1.3, "Knockback", 70, 30, 0.25, 1.9 },
				{ 1.6, "Knockback", 0, 60, 0.25, 1.9 },
				{ 1.9, "Knockback", 80, 28, 0.25, 1.9 },
				{ 4.0, "Knockback", 0, 60, 0.25, 1.9 },
				{ 4.3, "Knockback", 0, 60, 0.25, 1.9 },
			},
		}, "clean")
	end
	case({
		Name = "Rupture at one-way 0.5 (RTT 1s)",
		Seconds = 5,
		Latency = 0.5,
		Fps = 15,
		Grants = { { 1, "Knockback", 0, 60, 0.25, 1.9 } },
	}, "clean")
	case({
		Name = "jump + double jump at apex, walking",
		Seconds = 4,
		Latency = 0.1,
		Walk = walk(16),
		Jumps = { 1 },
		DoubleJumps = { 1.25 },
	}, "clean")
	case({
		Name = "jump + double jump late (falling), walking",
		Seconds = 4,
		Latency = 0.1,
		Walk = walk(16),
		Jumps = { 1 },
		DoubleJumps = { 1.6 },
	}, "clean")
	case({
		Name = "jump + double jump + dash hover at apex",
		Seconds = 5,
		Latency = 0.1,
		Walk = walk(16),
		Jumps = { 1 },
		DoubleJumps = { 1.25 },
		Grants = { { 1.45, "Dash", 100, 0, 0.22, 0.9 } },
	}, "clean")
	case({
		Name = "jump, double jump, Sweep lift at apex (fps 10)",
		Seconds = 5,
		Latency = 0.1,
		Fps = 10,
		Jumps = { 1 },
		DoubleJumps = { 1.25 },
		Grants = { { 1.4, "Knockback", 70, 30, 0.25, 1.9 } },
	}, "clean")
	case({
		Name = "Ligature in the air (20 in 0.25)",
		Seconds = 4,
		Latency = 0.2,
		Jumps = { 1 },
		Grants = { { 1.2, "Dash", 80, 0, 0.25, 0.9 } },
	}, "clean")
	case({
		Name = "walk off the boss arena (900) into the hub",
		Seconds = 9,
		Latency = 0.1,
		Walk = walk(16),
		StartX = 60,
		StartY = 903,
		Floors = BOSS_FALL,
	}, "clean")
	case({
		Name = "fall 900 with an uplink stall mid-fall",
		Seconds = 9,
		Latency = 0.1,
		Walk = walk(16),
		StartX = 60,
		StartY = 903,
		Stalls = { { 1.8, 3.0 } },
		Floors = BOSS_FALL,
	}, "clean")
	for _, L in ipairs({ 0.05, 0.5 }) do
		case({
			Name = ("server teleport hub->arena 500 up, stale samples L=%.2f"):format(L),
			Seconds = 6,
			Latency = L,
			Walk = walk(8),
			Floors = ARENA,
			Teleports = { { 2, 0, 503 } },
		}, "clean")
	end
	case({
		Name = "Caret mid-dash (18 studs, leftover dash)",
		Seconds = 5,
		Latency = 0.15,
		Walk = walk(16),
		Grants = { { 2, "Dash", 100, 0, 0.22, 0.9 } },
		Teleports = { { 2.25, 55, 3 } },
	}, "clean")
	case({
		Name = "ragdoll after finisher",
		Seconds = 4,
		Latency = 0.1,
		Grants = { { 1, "Knockback", 45, 18, 0.25, 1.9 } },
		Down = { { 1, 2.3 } },
	}, "clean")
	case({
		Name = "triple Rupture juggle, fps 10",
		Seconds = 5,
		Latency = 0.1,
		Fps = 10,
		Grants = {
			{ 1.0, "Knockback", 0, 60, 0.25, 1.9 },
			{ 1.3, "Knockback", 0, 60, 0.25, 1.9 },
			{ 1.6, "Knockback", 0, 60, 0.25, 1.9 },
		},
	}, "clean")
	case({
		Name = "Rupture then Fury at one-way 0.9 s (RTT 1.8)",
		Seconds = 6,
		Latency = 0.9,
		Fps = 30,
		Grants = { { 1.0, "Knockback", 0, 60, 0.25, 1.9 }, { 1.2, "Knockback", 80, 28, 0.25, 1.9 } },
	}, "clean")
	case({
		Name = "apex: Hairline push, dash, Ligature chained",
		Seconds = 5,
		Latency = 0.1,
		Jumps = { 1 },
		DoubleJumps = { 1.25 },
		Grants = {
			{ 1.4, "Knockback", 14, 0, 0.25, 1.9 },
			{ 1.62, "Dash", 100, 0, 0.22, 0.9 },
			{ 1.82, "Dash", 80, 0, 0.25, 0.9 },
		},
	}, "clean")
	case({
		Name = "one replicated sample 40 studs off (glitch)",
		Seconds = 4,
		Latency = 0.1,
		Walk = walk(16),
		Spike = { 2, 2.04, 40 },
	}, "clean")
	case({
		Name = "server teleport 500 up, uplink bursts every 0.3 s",
		Seconds = 6,
		Latency = 0.3,
		SendEvery = 0.3,
		Walk = walk(8),
		Floors = ARENA,
		Teleports = { { 2, 0, 503 } },
	}, "clean")
	case({
		Name = "double jump, Brand lift 20 at the apex",
		Seconds = 5,
		Latency = 0.1,
		Fps = 15,
		Jumps = { 1 },
		DoubleJumps = { 1.25 },
		Grants = { { 1.42, "Knockback", 40, 20, 0.25, 1.9 } },
	}, "clean")
	case({
		Name = "Margin wall rises under a standing player (contact latch)",
		Seconds = 5,
		Latency = 0.1,
		Floors = { { X0 = -1e9, X1 = 1e9, Top = 0 } },
		Walls = { { X0 = -1.25, X1 = 1.25, Bottom = 0, Top = 9 } },
		Cheat = function(t: number): (number?, number?)
			if t >= 2 and t < 2.22 then
				return nil, 3 + 9 * (t - 2) / 0.22
			end
			return nil, nil
		end,
		Contact = { { 2, 2.3 } },
	}, "clean")
end)

describe("MovementScenarios: honest, the false-positive critic's cases", function()
	for _, L in ipairs({ 0.05, 0.15, 0.3 }) do
		case({
			Name = ("spawn at pad edge, walk + dash at 0.4s, L=%.2f"):format(L),
			Seconds = 4,
			Latency = L,
			StartX = 8,
			SpawnPoint = { 8, 3 },
			Walk = walk(16),
			Grants = { { 0.4, "Dash", 100, 0, 0.22, 0.9 } },
		}, "clean")
		case({
			Name = ("spawn, dash 0.4 + Ligature 0.9, L=%.2f"):format(L),
			Seconds = 4,
			Latency = L,
			StartX = 8,
			SpawnPoint = { 8, 3 },
			Walk = walk(16),
			Grants = { { 0.4, "Dash", 100, 0, 0.22, 0.9 }, { 0.9, "Dash", 80, 0, 0.25, 0.9 } },
		}, "clean")
	end
	for _, extra in ipairs({ 0.2, 0.35, 0.5, 0.8, 1.0 }) do
		case({
			Name = ("walk, Rupture on ground, fps 15, +%.2fs downlink"):format(extra),
			Seconds = 5,
			Latency = 0.15,
			Fps = 15,
			Walk = walk(16),
			Grants = { { 1.0, "Knockback", 0, 60, 0.25, 1.9 } },
			DownDelay = { { 0.99, 1.01, extra } },
		}, "clean")
		case({
			Name = ("walk, jump, Rupture at apex, fps 60, +%.2fs downlink"):format(extra),
			Seconds = 5,
			Latency = 0.15,
			Walk = walk(16),
			Jumps = { 1.0 + 0.15 + extra - 0.25 },
			Grants = { { 1.0, "Knockback", 0, 60, 0.25, 1.9 } },
			DownDelay = { { 0.99, 1.01, extra } },
		}, "clean")
		case({
			Name = ("walk, Dash then Ligature chained, +%.2fs downlink"):format(extra),
			Seconds = 5,
			Latency = 0.15,
			Fps = 30,
			Walk = walk(16),
			Grants = { { 1.0, "Dash", 100, 0, 0.22, 0.9 }, { 1.25, "Dash", 80, 0, 0.25, 0.9 } },
			DownDelay = { { 0.99, 1.3, extra } },
		}, "clean")
		case({
			Name = ("walk, dash, fps 10, +%.2fs downlink"):format(extra),
			Seconds = 5,
			Latency = 0.15,
			Fps = 10,
			Walk = walk(16),
			Grants = { { 1.0, "Dash", 100, 0, 0.22, 0.9 } },
			DownDelay = { { 0.99, 1.01, extra } },
		}, "clean")
	end
	for _, extra in ipairs({ 0.0, 0.3, 0.6, 1.0 }) do
		local arrive = T0 + 0.15 + extra
		case({
			Name = ("Sweep at double-jump apex, fps 60, +%.2fs downlink"):format(extra),
			Seconds = 8,
			Latency = 0.15,
			Walk = walk(16),
			Jumps = { arrive - 0.51 },
			DoubleJumps = { arrive - 0.255 },
			Grants = { { T0, "Knockback", 70, 30, 0.25, 1.9 } },
			DownDelay = { { T0 - 0.01, T0 + 0.01, extra } },
		}, "clean")
		case({
			Name = ("Rupture at jump apex, fps 30, +%.2fs downlink"):format(extra),
			Seconds = 8,
			Latency = 0.15,
			Fps = 30,
			Walk = walk(16),
			Jumps = { arrive - 0.255 },
			Grants = { { T0, "Knockback", 0, 60, 0.25, 1.9 } },
			DownDelay = { { T0 - 0.01, T0 + 0.01, extra } },
		}, "clean")
		case({
			Name = ("Rupture on the ground, fps 10, +%.2fs downlink"):format(extra),
			Seconds = 8,
			Latency = 0.15,
			Fps = 10,
			Walk = walk(16),
			Grants = { { T0, "Knockback", 0, 60, 0.25, 1.9 } },
			DownDelay = { { T0 - 0.01, T0 + 0.01, extra } },
		}, "clean")
	end
	for _, h in ipairs({ { 4.2, 4.5 }, { 4.8, 5.1 }, { 5.4, 5.7 }, { 6.0, 6.3 }, { 6.3, 6.6 } }) do
		case({
			Name = ("fall 900, server hitch %.1f-%.1f"):format(h[1], h[2]),
			Seconds = 9,
			Latency = 0.1,
			Walk = walk(16),
			StartX = 20,
			StartY = 903,
			Floors = BOSS_FALL,
			ServerHitch = { h },
		}, "clean")
	end
	for _, h in ipairs({ { 5.0, 5.2, 0.3 }, { 5.5, 5.7, 0.5 }, { 6.0, 6.2, 0.6 } }) do
		case({
			Name = ("fall 900, uplink +%.1fs at %.1f"):format(h[3], h[1]),
			Seconds = 9,
			Latency = 0.1,
			Walk = walk(16),
			StartX = 20,
			StartY = 903,
			Floors = BOSS_FALL,
			UpDelay = { h },
		}, "clean")
	end
	for _, fps in ipairs({ 60, 15, 10 }) do
		for _, L in ipairs({ 0.05, 0.15 }) do
			case({
				Name = ("dash+Caret same instant, fps %d L=%.2f, walk on"):format(fps, L),
				Seconds = 9,
				Latency = L,
				Fps = fps,
				Walk = walk(16),
				Grants = { { 4.0, "Dash", 100, 0, 0.22, 0.9 } },
				Teleports = { { 4.0, 55, 3 } },
			}, "clean")
		end
	end
	for _, dt in ipairs({ 0.05, 0.1, 0.15 }) do
		case({
			Name = ("boss Fury at 2.0, hub return pivot at %.2f, walk"):format(2.0 + dt),
			Seconds = 7,
			Latency = 0.15,
			Fps = 20,
			Walk = walk(16),
			Grants = { { 2, "Knockback", 80, 28, 0.25, 1.9 } },
			Teleports = { { 2.0 + dt, 60, 3 } },
		}, "clean")
	end
	it("clean: hop onto a Margin wall and again, 45 variants", function()
		local failures = {}
		for _, send in ipairs({ 0.05, 0.1, 0.133 }) do
			for i = 0, 14 do
				local jumpAt = 3.53 + i * 0.01
				local stats = Sim.run({
					Name = "hop",
					Seconds = 7,
					Latency = 0.1,
					Walk = walk(16),
					StartX = 0,
					SendEvery = send,
					Floors = { { X0 = -1e9, X1 = 1e9, Top = 0 } },
					Walls = { { X0 = 67.5, X1 = 70, Bottom = 0, Top = 9 } },
					Jumps = { jumpAt },
					DoubleJumps = { jumpAt + 0.255 },
					AutoJumpOn = 9,
				})
				if not Sim.meets(stats, "clean") then
					table.insert(failures, ("send %.3f jump %.2f: %s"):format(send, jumpAt, Sim.describe(stats)))
				end
			end
		end
		if #failures > 0 then
			error(table.concat(failures, "\n"), 0)
		end
	end)
	for _, L in ipairs({ 0.05, 0.15 }) do
		for _, st in ipairs({ 0.6, 1.0, 1.5, 2.0 }) do
			for _, fps in ipairs({ 60, 15 }) do
				case({
					Name = ("Dash+Ligature, stall %.1fs from dash start, L=%.2f fps %d"):format(st, L, fps),
					Seconds = 9,
					Latency = L,
					Fps = fps,
					Walk = walk(16),
					Grants = { { T0, "Dash", 100, 0, 0.22, 0.9 }, { T0 + 0.3, "Dash", 80, 0, 0.25, 0.9 } },
					Stalls = { { T0 + L, T0 + L + st } },
				}, "clean")
			end
		end
	end
	for _, fps in ipairs({ 30, 15, 10 }) do
		for _, st in ipairs({ 0.6, 0.8, 0.95 }) do
			case({
				Name = ("boss Fury, fps %d, stall %.2fs"):format(fps, st),
				Seconds = 9,
				Latency = 0.1,
				Fps = fps,
				Walk = walk(16),
				Grants = { { T0, "Knockback", 80, 28, 0.25, 1.9 } },
				Stalls = { { T0 + 0.1, T0 + 0.1 + st } },
			}, "clean")
		end
	end
	for _, L in ipairs({ 0.5, 0.7, 0.9 }) do
		case({
			Name = ("walking, Rupture on ground fps 15, one-way %.1f"):format(L),
			Seconds = 10,
			Latency = L,
			Fps = 15,
			Walk = walk(16),
			Grants = { { 5, "Knockback", 0, 60, 0.25, 1.9 } },
		}, "clean")
		case({
			Name = ("walking, jump, Rupture at apex fps 60, one-way %.1f"):format(L),
			Seconds = 10,
			Latency = L,
			Walk = walk(16),
			Jumps = { 5 + L - 0.255 },
			Grants = { { 5, "Knockback", 0, 60, 0.25, 1.9 } },
		}, "clean")
	end
	for _, send in ipairs({ 0.05, 0.075, 0.1, 0.133 }) do
		case({
			Name = ("glitch sample, replication every %.3f s"):format(send),
			Seconds = 8,
			Latency = 0.1,
			Walk = walk(16),
			SendEvery = send,
			Spike = { 4, 4 + send - 0.001, 40 },
		}, "clean")
	end
end)

describe("MovementScenarios: honest, slows, walls, shoves and respawns", function()
	case({
		Name = "match freeze 5 s after placement, standing still",
		Seconds = 8,
		Latency = 0.2,
		Floors = ARENA,
		Teleports = { { 1, 0, 503 } },
		WalkSpeedAt = function(t: number): number
			return if t >= 1 and t < 6 then 0 else 16
		end,
	}, "clean")
	case({
		Name = "walking while blocking (WalkSpeed 8)",
		Seconds = 10,
		Latency = 0.2,
		Walk = walk(8),
		WalkSpeedAt = walk(8),
	}, "clean")
	case({
		Name = "block released: 8 -> 16, client learns late",
		Seconds = 10,
		Latency = 0.3,
		Walk = function(t: number): number
			return if t < 5.3 then 8 else 16
		end,
		WalkSpeedAt = function(t: number): number
			return if t < 5 then 8 else 16
		end,
	}, "clean")
	case({
		Name = "slowed to 0.4 while walking, client learns late",
		Seconds = 10,
		Latency = 0.3,
		Walk = function(t: number): number
			return if t < 3.3 then 16 elseif t < 6.3 then 6.4 else 16
		end,
		WalkSpeedAt = function(t: number): number
			return if t >= 3 and t < 6 then 6.4 else 16
		end,
	}, "clean")
	case({
		Name = "jump over a 6-high cover wall, 20 Hz",
		Seconds = 6,
		Latency = 0.1,
		Walk = walk(16),
		Walls = COVER_WALL,
		Jumps = { 2.3 },
		DoubleJumps = { 2.55 },
	}, "clean")
	for _, send in ipairs({ 0.1, 0.3 }) do
		case({
			Name = ("jump over a 6-high cover wall, replication every %.1f s"):format(send),
			Seconds = 6,
			Latency = 0.1,
			SendEvery = send,
			Walk = walk(16),
			Walls = COVER_WALL,
			Jumps = { 2.3 },
			DoubleJumps = { 2.55 },
		}, "clean")
	end
	case({
		Name = "stand on a Margin wall (9), double jump off it",
		Seconds = 6,
		Latency = 0.1,
		StartX = 1,
		StartY = 12,
		SpawnPoint = { 1, 12 },
		Walls = { { X0 = 0, X1 = 2.5, Bottom = 0, Top = 9 } },
		Walk = function(t: number): number
			return if t > 2 then 16 else 0
		end,
		Jumps = { 2.0 },
		DoubleJumps = { 2.255 },
	}, "clean")
	case({
		Name = "boss shove: contact, pushed 18 studs/s for 2 s",
		Seconds = 6,
		Latency = 0.1,
		Contact = { { 2, 4 } },
		Cheat = function(t: number): (number?, number?)
			if t >= 2 and t < 4 then
				return 18 * (t - 2), nil
			elseif t >= 4 then
				return 36, nil
			end
			return nil, nil
		end,
	}, "clean")
	case({
		Name = "fling victim: rammed, thrown 600 studs/s for 0.1 s",
		Seconds = 6,
		Latency = 0.1,
		Contact = { { 2, 2.06 } },
		Cheat = function(t: number): (number?, number?)
			if t >= 2.05 and t < 2.15 then
				return 600 * (t - 2.05), 3 + 100 * (t - 2.05)
			elseif t >= 2.15 then
				return 60, nil
			end
			return nil, nil
		end,
	}, "nostrike")
	case({
		Name = "respawn in the hub then placed on a pad (stale spawn samples)",
		Seconds = 5,
		Latency = 0.3,
		StartX = 5,
		SpawnPoint = { 5, 3 },
		Floors = ARENA,
		Walk = walk(16),
		Teleports = { { 0.2, 0, 503 } },
	}, "clean")
	case({
		Name = "stand 12 s then walk 16",
		Seconds = 16,
		Latency = 0.1,
		Walk = function(t: number): number
			return if t > 12 then 16 else 0
		end,
	}, "clean")
	case({
		Name = "glitch sample through a cover wall, then back",
		Seconds = 6,
		Latency = 0.1,
		Walk = walk(16),
		Walls = COVER_WALL,
		Spike = { 2.4, 2.44, 6 },
	}, "clean")
	case({
		Name = "glitch sample under the floor, then back",
		Seconds = 6,
		Latency = 0.1,
		StartY = 503,
		Floors = ARENA,
		Walk = walk(16),
		Spike = { 2.4, 2.44, 0, -20 },
	}, "clean")
end)

describe("MovementScenarios: honest, a misread round trip and uplink jitter", function()
	for _, scale in ipairs({ 0.5, 0.25 }) do
		for _, L in ipairs({ 0.1, 0.3, 0.5 }) do
			case({
				Name = ("dash while walking, fps 15, L=%.1f, Rtt read x%.2f"):format(L, scale),
				Seconds = 6,
				Latency = L,
				Fps = 15,
				RttScale = scale,
				Walk = walk(16),
				Grants = { { 2, "Dash", 100, 0, 0.22, 0.9 }, { 4.6, "Dash", 100, 0, 0.22, 0.9 } },
			}, "clean")
			case({
				Name = ("juggle fps 15, L=%.1f, Rtt read x%.2f"):format(L, scale),
				Seconds = 8,
				Latency = L,
				Fps = 15,
				RttScale = scale,
				Grants = {
					{ 1.0, "Knockback", 45, 18, 0.25, 1.9 },
					{ 1.3, "Knockback", 70, 30, 0.25, 1.9 },
					{ 1.6, "Knockback", 0, 60, 0.25, 1.9 },
					{ 1.9, "Knockback", 80, 28, 0.25, 1.9 },
				},
			}, "clean")
			case({
				Name = ("jump, Rupture at apex, L=%.1f, Rtt read x%.2f"):format(L, scale),
				Seconds = 6,
				Latency = L,
				RttScale = scale,
				Walk = walk(16),
				Jumps = { 2 + L - 0.255 },
				Grants = { { 2, "Knockback", 0, 60, 0.25, 1.9 } },
			}, "clean")
			case({
				Name = ("server teleport 500 up, L=%.1f, Rtt read x%.2f"):format(L, scale),
				Seconds = 6,
				Latency = L,
				RttScale = scale,
				Walk = walk(8),
				Floors = ARENA,
				Teleports = { { 2, 0, 503 } },
			}, "clean")
			case({
				Name = ("Caret mid-dash, L=%.1f, Rtt read x%.2f"):format(L, scale),
				Seconds = 5,
				Latency = L,
				RttScale = scale,
				Walk = walk(16),
				Grants = { { 2, "Dash", 100, 0, 0.22, 0.9 } },
				Teleports = { { 2.25, 55, 3 } },
			}, "clean")
		end
	end
	for seed = 1, 6 do
		for _, J in ipairs({ 0.1, 0.25 }) do
			case({
				Name = ("walk + dash + jumps, uplink jitter %.2f s, seed %d"):format(J, seed),
				Seconds = 10,
				Latency = 0.1,
				Jitter = J,
				Seed = seed,
				Fps = 30,
				Walk = walk(16),
				Jumps = { 1.5, 5.5 },
				DoubleJumps = { 1.75, 5.8 },
				Grants = { { 3, "Dash", 100, 0, 0.22, 0.9 }, { 7, "Knockback", 70, 30, 0.25, 1.9 } },
			}, "clean")
			case({
				Name = ("fall 900, uplink jitter %.2f s, seed %d"):format(J, seed),
				Seconds = 9,
				Latency = 0.1,
				Jitter = J,
				Seed = seed,
				Walk = walk(16),
				StartX = 20,
				StartY = 903,
				Floors = BOSS_FALL,
			}, "clean")
		end
	end
end)

describe("MovementScenarios: honest, stalls the server cannot tell from a cheat", function()
	case({
		Name = "uplink stall at a jump apex, 4 s, silent (no remote arrives)",
		Seconds = 8,
		Latency = 0.1,
		Walk = walk(16),
		Jumps = { 1 },
		DoubleJumps = { 1.25 },
		Stalls = { { 1.4, 5.4 } },
	}, "clean")
	case({
		Name = "physics throttled at an apex 4 s while remotes arrive (unverified case)",
		Seconds = 8,
		Latency = 0.1,
		RemotesAlways = true,
		Walk = walk(16),
		Jumps = { 1 },
		DoubleJumps = { 1.25 },
		Stalls = { { 1.4, 5.4 } },
	}, "clean")
	case({
		Name = "server teleport, downlink stalls 8 s, silent",
		Seconds = 14,
		Latency = 0.1,
		Walk = walk(8),
		Floors = ARENA,
		Teleports = { { 2, 0, 503 } },
		DownStall = { 1.9, 10 },
	}, "nostrike")
	for _, st in ipairs({ 1, 2, 3, 5 }) do
		case({
			Name = ("server teleport, downlink stalls %d s, silent"):format(st),
			Seconds = 12,
			Latency = 0.1,
			Walk = walk(16),
			Floors = ARENA,
			Teleports = { { 2, 0, 503 } },
			DownStall = { 1.9, 2 + st },
		}, "nostrike")
	end
end)

describe("MovementScenarios: honest, the cases that pin a rule's margin", function()
	for _, fps in ipairs({ 6, 5 }) do
		case({
			Name = ("juggle finisher/Sweep/Rupture/Fury fps %d"):format(fps),
			Seconds = 8,
			Latency = 0.15,
			Fps = fps,
			Grants = {
				{ 1.0, "Knockback", 45, 18, 0.25, 1.9 },
				{ 1.3, "Knockback", 70, 30, 0.25, 1.9 },
				{ 1.6, "Knockback", 0, 60, 0.25, 1.9 },
				{ 1.9, "Knockback", 80, 28, 0.25, 1.9 },
			},
		}, "clean")
		case({
			Name = ("jump, double jump, Rupture at apex fps %d"):format(fps),
			Seconds = 6,
			Latency = 0.1,
			Fps = fps,
			Jumps = { 1 },
			DoubleJumps = { 1.25 },
			Grants = { { 1.35, "Knockback", 0, 60, 0.25, 1.9 } },
		}, "clean")
		case({
			Name = ("boss Fury then Sweep while walking fps %d"):format(fps),
			Seconds = 6,
			Latency = 0.1,
			Fps = fps,
			Walk = walk(16),
			Grants = { { 2, "Knockback", 80, 28, 0.25, 1.9 }, { 2.3, "Knockback", 70, 30, 0.25, 1.9 } },
		}, "clean")
	end
	case({
		Name = "fling victim thrown 30 studs per tick for 1.5 s",
		Seconds = 8,
		Latency = 0.1,
		Contact = { { 2, 2.06 } },
		Cheat = function(t: number): (number?, number?)
			if t >= 2.05 and t < 3.55 then
				return 600 * (t - 2.05), nil
			elseif t >= 3.55 then
				return 900, nil
			end
			return nil, nil
		end,
	}, "nostrike")
	case({
		Name = "walk 16 while the boss pushes 18 the same way for 3 s",
		Seconds = 8,
		Latency = 0.1,
		Walk = walk(16),
		Contact = { { 2, 5 } },
		Cheat = function(t: number, x: number): (number?, number?)
			if t >= 2 and t < 5 then
				return x + 18 / 240, nil
			end
			return nil, nil
		end,
	}, "clean")
	case({
		Name = "walk + uplink stall 16 s (beyond the forgiven bank)",
		Seconds = 22,
		Latency = 0.1,
		Walk = walk(16),
		Stalls = { { 2, 18 } },
	}, "nostrike")
	case({
		Name = "one non-finite replicated sample, then normal",
		Seconds = 5,
		Latency = 0.1,
		Walk = walk(16),
		Spike = { 2, 2.04, math.huge },
	}, "clean")
end)

-- lowfps.luau's cases at 6 and 5 fps that the group above does not already run: honest down to 5 fps.
describe("MovementScenarios: honest, low frame rates", function()
	for _, fps in ipairs({ 6, 5 }) do
		case({
			Name = ("boss Fury alone fps %d"):format(fps),
			Seconds = 6,
			Latency = 0.1,
			Fps = fps,
			Walk = walk(16),
			Grants = { { 2, "Knockback", 80, 28, 0.25, 1.9 } },
		}, "clean")
		case({
			Name = ("dash + Ligature fps %d"):format(fps),
			Seconds = 6,
			Latency = 0.1,
			Fps = fps,
			Walk = walk(16),
			Grants = { { 2, "Dash", 100, 0, 0.22, 0.9 }, { 2.3, "Dash", 80, 0, 0.25, 0.9 } },
		}, "clean")
	end
end)

describe("MovementScenarios: cheats, the draft's cases", function()
	case(
		{ Name = "speed hack 30 studs/s (under the 40 ceiling)", Seconds = 8, Latency = 0.1, Walk = walk(30) },
		"strike"
	)
	case({ Name = "speed hack 60 studs/s", Seconds = 6, Latency = 0.1, Walk = walk(60) }, "strike")
	case({ Name = "speed hack 540 studs/s", Seconds = 3, Latency = 0.1, Walk = walk(540) }, "strike")
	case({
		Name = "idle 2 s, then teleport 100 studs sideways (catch-up: corrected)",
		Seconds = 4,
		Latency = 0.1,
		Cheat = function(t: number): (number?, number?)
			return if t > 2 then 100 else nil, nil
		end,
	}, "correct")
	case({
		Name = "walking, then teleport 100 studs ahead",
		Seconds = 5,
		Latency = 0.1,
		Walk = walk(16),
		Cheat = function(t: number, x: number): (number?, number?)
			if t > 2 and t < 2.1 then
				return x + 100, nil
			end
			return nil, nil
		end,
	}, "strike")
	case({
		Name = "teleport 500 up (to the arena above)",
		Seconds = 4,
		Latency = 0.1,
		Floors = ARENA,
		Cheat = function(t: number): (number?, number?)
			return nil, if t > 2 then 503 else nil
		end,
	}, "strike")
	case({
		Name = "teleport 500 down (arena to the hub)",
		Seconds = 5,
		Latency = 0.1,
		StartY = 503,
		Floors = ARENA,
		Cheat = function(t: number): (number?, number?)
			return nil, if t > 2 then 3 else nil
		end,
	}, "strike")
	case({
		Name = "fly up at 20 studs/s",
		Seconds = 5,
		Latency = 0.1,
		Cheat = function(t: number): (number?, number?)
			return nil, if t > 2 then 3 + 20 * (t - 2) else nil
		end,
	}, "strike")
	case({
		Name = "hover 10 studs up while strafing",
		Seconds = 5,
		Latency = 0.1,
		Walk = walk(16),
		Cheat = function(t: number): (number?, number?)
			return nil, if t > 2 then 13 else nil
		end,
	}, "strike")
	case({
		Name = "glide down at 5 studs/s from 15",
		Seconds = 5,
		Latency = 0.1,
		Walk = walk(16),
		Cheat = function(t: number): (number?, number?)
			return nil, if t > 2 then math.max(3, 18 - 5 * (t - 2)) else nil
		end,
	}, "strike")
	case({
		Name = "stationary hover 12 up, still acting (remotes arrive)",
		Seconds = 12,
		Latency = 0.1,
		RemotesAlways = true,
		Cheat = function(t: number): (number?, number?)
			return nil, if t > 2 then 15 else nil
		end,
	}, "strike")
	case({
		Name = "stationary hover 12 up, silent (indistinguishable from a stall)",
		Seconds = 12,
		Latency = 0.1,
		Cheat = function(t: number): (number?, number?)
			return nil, if t > 2 then 15 else nil
		end,
	}, "nostrike")
	case({
		Name = "teleport 100 then refuse the pivot (remotes arrive)",
		Seconds = 14,
		Latency = 0.1,
		RemotesAlways = true,
		CheatIgnoresPivot = true,
		Cheat = function(t: number): (number?, number?)
			return if t > 2 then 100 else nil, nil
		end,
	}, "strike")
	case({
		Name = "hover 12 up from spawn (inside the spawn grace)",
		Seconds = 8,
		Latency = 0.1,
		Walk = walk(16),
		Cheat = function(t: number): (number?, number?)
			return nil, if t > 0.5 then 15 else nil
		end,
	}, "strike")
end)

describe("MovementScenarios: cheats, the exploit critic's cases", function()
	case({
		Name = "A gentle climb 0.3/0.55s, walk 16",
		Seconds = 32,
		Latency = 0.1,
		Walk = walk(16),
		Cheat = function(t: number): (number?, number?)
			if t <= 2 then
				return nil, nil
			end
			return nil, 5 + 0.3 * math.floor((t - 2) / 0.55)
		end,
	}, "strike")
	case({
		Name = "A2 gentle climb at walk 23",
		Seconds = 32,
		Latency = 0.1,
		Walk = walk(23),
		Cheat = function(t: number): (number?, number?)
			if t <= 2 then
				return nil, nil
			end
			return nil, 5 + 0.3 * math.floor((t - 2) / 0.55)
		end,
	}, "strike")
	case({
		Name = "pophover: hover 10 up, one-tick pop +0.26 every 0.6 s",
		Seconds = 20,
		Latency = 0.1,
		Walk = walk(16),
		Cheat = function(t: number): (number?, number?)
			if t < 2 then
				return nil, nil
			end
			local phase = (t - 2) % 0.6
			if phase < 0.05 then
				return nil, 14 + 0.26 * math.floor((t - 2) / 0.6)
			end
			return nil, 13
		end,
	}, "strike")
	for _, period in ipairs({ 2, 3, 6 }) do
		case({
			Name = ("flicker: one packet in %d replicated 100 studs aside"):format(period),
			Seconds = 20,
			Latency = 0.1,
			Walk = walk(16),
			FlickerPeriod = period,
		}, "correct")
	end
	case({
		Name = "B blink 44 every 1.25 s",
		Seconds = 22,
		Latency = 0.1,
		Cheat = function(t: number): (number?, number?)
			if t <= 2 then
				return nil, nil
			end
			return 44 * (1 + math.floor((t - 2) / 1.25)), nil
		end,
	}, "strike")
	case({
		Name = "B2 blink 44 every 1.9 s (23 studs/s avg)",
		Seconds = 32,
		Latency = 0.1,
		Cheat = function(t: number): (number?, number?)
			if t <= 2 then
				return nil, nil
			end
			return 44 * (1 + math.floor((t - 2) / 1.9)), nil
		end,
	}, "strike")
	for _, far in ipairs({ 380, 395 }) do
		case({
			Name = ("C 5 unplayed dashes, still, then blink %d"):format(far),
			Seconds = 17,
			Latency = 0.1,
			IgnoreGrants = true,
			Grants = {
				{ 2, "Dash", 100, 0, 0.22, 0.9 },
				{ 4.6, "Dash", 100, 0, 0.22, 0.9 },
				{ 7.2, "Dash", 100, 0, 0.22, 0.9 },
				{ 9.8, "Dash", 100, 0, 0.22, 0.9 },
				{ 12.4, "Dash", 100, 0, 0.22, 0.9 },
			},
			Cheat = function(t: number): (number?, number?)
				return if t < 14 then 0 else far, 3
			end,
		}, "correct")
	end
	case({
		Name = "L one dash never played, 30 s still, then blink 250",
		Seconds = 33,
		Latency = 0.1,
		IgnoreGrants = true,
		Grants = { { 0.5, "Dash", 100, 0, 0.22, 0.9 } },
		Cheat = function(t: number): (number?, number?)
			return if t < 30.5 then 0 else 250, 3
		end,
	}, "correct")
	for _, L in ipairs({ 0.1, 0.5 }) do
		local off = if L == 0.1 then 50 else 66
		case({
			Name = ("E Caret to x=0 then sit %d studs away, L=%.1f"):format(off, L),
			Seconds = 8,
			Latency = L,
			StartX = -18,
			SpawnPoint = { -18, 3 },
			Teleports = { { 2, 0, 3 } },
			Cheat = function(t: number): (number?, number?)
				return if t > 2 + 2 * L + 0.02 then off else nil, nil
			end,
		}, "correct")
		case({
			Name = ("E2 Caret dest x=0, body goes to x=%d, L=%.1f"):format(off, L),
			Seconds = 8,
			Latency = L,
			StartX = -18,
			SpawnPoint = { -18, 3 },
			CheatIgnoresPivot = true,
			Teleports = { { 2, 0, 3 } },
			Cheat = function(t: number): (number?, number?)
				return if t >= 1.99 then off else nil, nil
			end,
		}, "correct")
	end
	case({ Name = "G speed hack 23 studs/s for 40 s", Seconds = 40, Latency = 0.1, Walk = walk(23) }, "strike")
	case({
		Name = "F 0.3 s server hitch hides a 300-stud teleport",
		Seconds = 5,
		Latency = 0.1,
		ServerHitch = { { 2, 2.3 } },
		Cheat = function(t: number): (number?, number?)
			return if t >= 2.1 then 300 else nil, nil
		end,
	}, "correct")
	case({
		Name = "cover-wall noclip at walking level",
		Seconds = 6,
		Latency = 0.1,
		Walk = walk(16),
		Walls = COVER_WALL,
		Cheat = function(t: number, x: number): (number?, number?)
			if x >= 39.9 and x < 42.5 and t < 5 then
				return 42.6, nil
			end
			return nil, nil
		end,
	}, "strike")
	case({
		Name = "arena-wall noclip after a 0.6 s blackout",
		Seconds = 6,
		Latency = 0.1,
		Walk = walk(16),
		Walls = { { X0 = 40, X1 = 42, Bottom = 0, Top = 24 } },
		Stalls = { { 2.2, 2.8 } },
		Cheat = function(_t: number, x: number): (number?, number?)
			if x >= 39.9 and x < 42.5 then
				return 42.6, nil
			end
			return nil, nil
		end,
	}, "strike")
	case({
		Name = "sink through the arena floor slowly",
		Seconds = 5,
		Latency = 0.1,
		StartY = 503,
		Floors = ARENA,
		Cheat = function(t: number): (number?, number?)
			if t > 2 then
				return nil, math.max(470, 503 - 20 * (t - 2))
			end
			return nil, nil
		end,
	}, "strike")
	case({
		Name = "one-tick drop 21 studs through the arena floor",
		Seconds = 5,
		Latency = 0.1,
		StartY = 503,
		Floors = ARENA,
		Cheat = function(t: number): (number?, number?)
			if t > 2 then
				return nil, 482
			end
			return nil, nil
		end,
	}, "strike")
	case({
		Name = "K one-tick pop 18.5 up onto a ledge",
		Seconds = 5,
		Latency = 0.1,
		Floors = { { X0 = -1e9, X1 = 1e9, Top = 0 }, { X0 = -5, X1 = 5, Top = 18.5 } },
		StartX = -20,
		Cheat = function(t: number): (number?, number?)
			if t > 2 then
				return 0, 21.5
			end
			return nil, nil
		end,
	}, "strike")
	case({
		Name = "inf sample",
		Seconds = 4,
		Latency = 0.1,
		Cheat = function(t: number): (number?, number?)
			if t > 2 and t < 2.05 then
				return math.huge, nil
			end
			return nil, nil
		end,
	}, "strike")
	case({
		Name = "D boss contact 8 s, then +1500 x / +150 y (latched)",
		Seconds = 12,
		Latency = 0.1,
		Contact = { { 1, 9.05 } },
		Walk = function(t: number): number
			return if t < 9 then 5 else 0
		end,
		Cheat = function(t: number): (number?, number?)
			if t >= 9 then
				return 1500, 153
			end
			return nil, nil
		end,
	}, "correct")
	for _, L in ipairs({ 0.1, 0.4 }) do
		local grants = {}
		for i = 0, 9 do
			table.insert(grants, { 1.9 + i * 2.5, "Dash", 100, 0, 0.22, 0.9 })
		end
		case({
			Name = ("dash every 2.5 s, hover 10 up strafing, one-way %.1f"):format(L),
			Seconds = 26,
			Latency = L,
			Walk = walk(16),
			Grants = grants,
			Cheat = function(t: number): (number?, number?)
				return nil, if t > 2 then 13 else nil
			end,
		}, "strike")
	end
	case({
		Name = "walk during the match freeze (16 studs/s)",
		Seconds = 8,
		Latency = 0.2,
		Floors = ARENA,
		Teleports = { { 1, 0, 503 } },
		Walk = function(t: number): number
			return if t > 1.6 then 16 else 0
		end,
		WalkSpeedAt = function(t: number): number
			return if t >= 1 and t < 7 then 0 else 16
		end,
	}, "strike")
end)

describe("MovementScenarios: cheats that pin a rule", function()
	case({
		Name = "teleport 300 down beside the arena (no barrier crossed)",
		Seconds = 5,
		Latency = 0.1,
		StartX = 50,
		StartY = 303,
		Floors = { { X0 = -1e9, X1 = 1e9, Top = 0 }, { X0 = 40, X1 = 60, Top = 300 } },
		Cheat = function(t: number): (number?, number?)
			return nil, if t > 2 then 3 else nil
		end,
	}, "strike")
	case({
		Name = "one-tick drop 21 through the arena floor, then free fall",
		Seconds = 5,
		Latency = 0.1,
		StartY = 503,
		Floors = ARENA,
		Cheat = function(t: number): (number?, number?)
			if t > 2 and t < 2.01 then
				return nil, 482
			end
			return nil, nil
		end,
	}, "strike")
	case({
		Name = "jump, one-tick drop through the arena floor at the apex, free fall",
		Seconds = 5,
		Latency = 0.1,
		StartY = 503,
		Floors = ARENA,
		Jumps = { 2 },
		Cheat = function(t: number): (number?, number?)
			if t > 2.26 and t < 2.265 then
				return nil, 480
			end
			return nil, nil
		end,
	}, "strike")
end)

-- A Dash granted every `period` s from 1 s to `seconds`: its cooldown, and its ink paid back by regeneration.
local function dashEvery(period: number, seconds: number): { Sim.Grant }
	local grants: { Sim.Grant } = {}
	for at = 1, seconds, period do
		table.insert(grants, { at, "Dash", 100, 0, 0.22, 0.9 })
	end
	return grants
end

-- A match or boss pad: ArenaService stands its marker a body's height (3.5) over the floor, and MatchService and
-- the Erasure's Encounter pivot the root 4 studs above the marker -- 4.5 studs over its standing height, in an
-- arena 900 studs above the hub the body comes from.
local PAD_FLOOR = 902
local PAD_ROOT = PAD_FLOOR + 3.5 + 4
local PAD_ARENA = { { X0 = -1e9, X1 = 1e9, Top = 0 }, { X0 = -60, X1 = 60, Top = PAD_FLOOR, Tagged = true } }

describe("MovementScenarios: honest, the adversarial review's cases", function()
	for _, L in ipairs({ 0.05, 0.1, 0.2 }) do
		for _, scale in ipairs({ 1, 2 }) do
			case({
				Name = ("pad drop 4.5 studs above standing, 900 up, hopping on landing, L=%.2f RTT x%d"):format(
					L,
					scale
				),
				Seconds = 6,
				Latency = L,
				RttScale = scale,
				Floors = PAD_ARENA,
				Teleports = { { 2, 0, PAD_ROOT } },
				AutoJumpOn = PAD_FLOOR,
			}, "clean")
		end
	end
	case({
		Name = "pad drop held at the destination 1.5 s (streaming), then falling onto the pad",
		Seconds = 6,
		Latency = 0.1,
		Floors = PAD_ARENA,
		Teleports = { { 2, 0, PAD_ROOT } },
		Cheat = function(t: number): (number?, number?)
			return nil, if t >= 2.1 and t < 3.6 then PAD_ROOT else nil
		end,
	}, "clean")
	case({
		Name = "walking 30 s with a Dash played on every cooldown",
		Seconds = 30,
		Latency = 0.05,
		RemotesAlways = true,
		Walk = walk(16),
		Grants = dashEvery(2.5, 30),
	}, "clean")
end)

describe("MovementScenarios: cheats, the adversarial review's cases", function()
	-- Shows the destination of every pivot for a moment, then puts the body back at `home`.
	local function bounceTo(home: number): (t: number, x: number) -> (number?, number?)
		local shownAt: number? = nil
		return function(t: number, x: number): (number?, number?)
			if math.abs(x - home) <= 1 then
				shownAt = nil
				return nil, nil
			end
			shownAt = shownAt or t
			return if t > (shownAt :: number) + 0.35 then home else nil, nil
		end
	end
	-- A Dash fired on every cooldown kept a grant awaiting its displacement two seconds out of 2.5, and an
	-- awaiting grant hid every segment from H2 and excused every flag: 0 strikes at up to 38 studs a second.
	for _, speed in ipairs({ 24, 30, 38 }) do
		case({
			Name = ("speed hack %d studs/s, a Dash granted on every cooldown and never played"):format(speed),
			Seconds = 30,
			Latency = 0.05,
			RemotesAlways = true,
			IgnoreGrants = true,
			Grants = dashEvery(2.5, 30),
			Walk = walk(speed),
		}, "strike")
	end
	-- A partner's light hits, one a second, keep a grant awaiting without a break: none may excuse the speed.
	local lightHits: { Sim.Grant } = {}
	for at = 1, 30 do
		table.insert(lightHits, { at, "Knockback", 10, 0, 0.25, 1.9 })
	end
	case({
		Name = "speed hack 30 studs/s under a partner's light hit every second, never played",
		Seconds = 30,
		Latency = 0.05,
		RemotesAlways = true,
		IgnoreGrants = true,
		Grants = lightHits,
		Walk = walk(30),
	}, "strike")
	for _, speed in ipairs({ 24, 34 }) do
		case({
			Name = ("speed hack %d studs/s, a Dash played on every cooldown"):format(speed),
			Seconds = 30,
			Latency = 0.05,
			RemotesAlways = true,
			Walk = walk(speed),
			Grants = dashEvery(2.5, 30),
		}, "strike")
	end
	-- A wall is 2 studs thick and a walk crosses 0.8 of it a tick: the stream puts a sample or two inside it, and the
	-- ray from the last sample never went through it -- in, then out, both from or to a point inside.
	for _, speed in ipairs({ 4, 16, 20 }) do
		for _, wall in ipairs({ COVER_WALL, { { X0 = 40, X1 = 42, Bottom = 0, Top = 24 } } }) do
			case({
				Name = ("noclip walking through a %d-high wall at %d studs/s, samples inside it"):format(
					wall[1].Top,
					speed
				),
				Seconds = 40 / speed + 4,
				Latency = 0.1,
				Walls = wall,
				Cheat = function(t: number): (number?, number?)
					return speed * t, nil
				end,
			}, "strike")
		end
	end
	-- Caret stops 3 studs short of the first obstruction, and a wall is 2 thick: its far side is inside the arrival
	-- radius, and the sample that showed the arrival was judged with no ray at all.
	case({
		Name = "Caret beside a 24-high wall, arriving on its far side",
		Seconds = 6,
		Latency = 0.05,
		StartX = 20,
		Walls = { { X0 = 40, X1 = 42, Bottom = 0, Top = 24 } },
		Teleports = { { 2, 37, 3 } },
		Cheat = function(_t: number, x: number): (number?, number?)
			return if x > 30 then 44 else nil, nil
		end,
	}, "strike")
	-- After ten seconds still, H1 lets a catch-up of over 200 studs through: the ray has to judge it.
	case({
		Name = "still 10.5 s, then a 205-stud blink through a 24-high wall",
		Seconds = 14,
		Latency = 0.05,
		Walls = { { X0 = 100, X1 = 102, Bottom = 0, Top = 24 } },
		Cheat = function(t: number): (number?, number?)
			return if t >= 10.5 then 205 else nil, nil
		end,
	}, "strike")
	case({
		Name = "back to the hub after a server teleport, and again after every correction",
		Seconds = 40,
		Latency = 0.05,
		RemotesAlways = true,
		Teleports = { { 2, 100, 3 } },
		Cheat = bounceTo(0),
	}, "strike")
	local blinkBack = bounceTo(100)
	case({
		Name = "blink 100, then back to the blink spot after every correction",
		Seconds = 40,
		Latency = 0.05,
		RemotesAlways = true,
		Cheat = function(t: number, x: number): (number?, number?)
			if t < 2 then
				return nil, nil
			end
			return blinkBack(t, x)
		end,
	}, "strike")
end)

-- The in-game review (D-137): every avatar judged from its own standing height, and a jump carried across a
-- server pivot. The developer's avatar stands 2.89 studs over its feet (tools/animations/rigs/developer.json),
-- today's default description 3.19, a small one under the support probe's 1.5-stud width, an Rthro one 4.5. A
-- client simulates its own body: a jump taken as a portal fires can keep rising from the destination
-- (KeepsMomentum), as the developer's session showed. Each case must be silent: not even a watch.
local AVATARS: { { any } } = { { "small", 1.4 }, { "the developer's", 2.89 }, { "default", 3.19 }, { "Rthro", 4.5 } }
-- The hub at 0, the Erasure's arena 900 over it, the Battleground's page at X = 1500.
local ERASURE_FLOOR = 900
local WORLD = {
	{ X0 = -100, X1 = 100, Top = 0, Tagged = true },
	{ X0 = -60, X1 = 60, Top = ERASURE_FLOOR, Tagged = true },
	{ X0 = 1415, X1 = 1585, Top = 0, Tagged = true },
}
-- Where each server placement puts a root: a boss or match pad, 4 studs over a marker that stands 3.5 over the
-- floor, and the hub's return ring and the Battleground's camp, 3.5 over the floor, whatever the avatar.
local ERASURE_PAD = ERASURE_FLOOR + 3.5 + 4
local LANDING = 3.5

local function steps(from: number, step: number, count: number): { number }
	local out: { number } = {}
	for i = 0, count - 1 do
		table.insert(out, from + i * step)
	end
	return out
end

-- Every combination of one value from each list, in order.
local function product(lists: { { number } }): { { number } }
	local rows: { { number } } = { {} }
	for _, list in ipairs(lists) do
		local grown: { { number } } = {}
		for _, row in ipairs(rows) do
			for _, value in ipairs(list) do
				local longer = table.clone(row)
				table.insert(longer, value)
				table.insert(grown, longer)
			end
		end
		rows = grown
	end
	return rows
end

-- One case over every row: silent on each, or a failure naming the rows that were not.
local function silentOver(label: string, rows: { { number } }, make: ({ number }) -> Sim.Scenario)
	it(("silent: %s, %d variants"):format(label, #rows), function()
		local failures = {}
		for _, row in ipairs(rows) do
			local stats = Sim.run(make(row))
			if not Sim.meets(stats, "silent") then
				local shown = {}
				for _, value in ipairs(row) do
					table.insert(shown, ("%g"):format(value))
				end
				table.insert(failures, ("%s: %s"):format(table.concat(shown, " "), Sim.describe(stats)))
			end
		end
		if #failures > 0 then
			error(table.concat(failures, "\n"), 0)
		end
	end)
end

-- A trip from `from` to `to` at 2 s, at 0.1 and 0.25 s one way: a jump taken in 5 ms steps around the moment the
-- pivot reaches the client, and the double jump 0.2 to 0.35 s after it, near its apex.
local function carriedJump(label: string, stand: number, from: { number }, to: { number })
	silentOver(label, product({ { 0.1, 0.25 }, steps(0, 0.005, 41), { 0.2, 0.25, 0.3, 0.35 } }), function(row)
		local jumpAt = 1.85 + row[1] + row[2]
		return {
			Name = label,
			Seconds = 4,
			Latency = row[1],
			Stand = stand,
			Floors = WORLD,
			StartX = from[1],
			StartY = from[2] + stand,
			Walk = walk(16),
			Jumps = { jumpAt },
			DoubleJumps = { jumpAt + row[3] },
			Teleports = { { 2, to[1], to[2] } },
			KeepsMomentum = true,
		}
	end)
end

describe("MovementScenarios: honest, every avatar from its own height (in-game review)", function()
	it("the simulator carries a jump across a pivot only for a client that keeps its momentum", function()
		-- A jump taken just before the pivot reaches the client, and the double jump near its apex.
		local function risesOverPad(keeps: boolean): number
			local stats = Sim.run({
				Name = "carried",
				Seconds = 4,
				Latency = 0.1,
				Floors = WORLD,
				Jumps = { 2.105 },
				DoubleJumps = { 2.4 },
				Teleports = { { 2, 0, ERASURE_PAD } },
				KeepsMomentum = keeps,
			})
			return stats.Peak - ERASURE_PAD
		end
		expect(risesOverPad(true)).toBeGreaterThan(10)
		expect(risesOverPad(false)).toBeLessThan(1)
	end)
	for _, avatar in ipairs(AVATARS) do
		local name, stand = avatar[1] :: string, avatar[2] :: number
		local who = ("%s avatar (%.2f)"):format(name, stand)
		case({
			Name = who .. ": spawn, walk, jump and double jump at the apex",
			Seconds = 6,
			Latency = 0.1,
			Stand = stand,
			RemotesAlways = true,
			Walk = walk(16),
			Jumps = { 1, 3.5 },
			DoubleJumps = { 1.255, 3.85 },
		}, "silent")
		case({
			Name = who .. ": spawn and bunny-hop, double jump at every apex",
			Seconds = 8,
			Latency = 0.1,
			Stand = stand,
			RemotesAlways = true,
			Walk = walk(16),
			Jumps = { 0.5 },
			DoubleJumps = { 0.755 },
			AutoJumpOn = 0,
		}, "silent")
		case({
			Name = who .. ": stands on a crate 8 s, remotes arriving",
			Seconds = 12,
			Latency = 0.1,
			Stand = stand,
			RemotesAlways = true,
			Floors = { { X0 = -1e9, X1 = 1e9, Top = 0 }, { X0 = 6, X1 = 14, Top = 4 } },
			Walk = function(t: number): number
				return if t < 2.6 then 4 else 0
			end,
			Jumps = { 1 },
			DoubleJumps = { 1.25 },
		}, "silent")
		-- A pad drops every root 7.5 studs over the floor: a small avatar falls 6.1 of them, once its client has
		-- the pivot. 19 latencies from 0.05 to 0.5 s one way, three jitters, the round trip read right and twice
		-- over, two seeds.
		silentOver(
			who .. ", a pad drop",
			product({ steps(0.05, 0.025, 19), { 0, 0.05, 0.1 }, { 1, 2 }, { 1, 2 } }),
			function(row)
				return {
					Name = "pad drop",
					Seconds = 5,
					Latency = row[1],
					Jitter = row[2],
					RttScale = row[3],
					Seed = row[4],
					Stand = stand,
					Floors = WORLD,
					Walk = walk(8),
					Teleports = { { 2, 0, ERASURE_PAD } },
				}
			end
		)
		carriedJump(who .. ", portal to the Erasure's arena while jumping", stand, { 0, 0 }, { 0, ERASURE_PAD })
		carriedJump(who .. ", return gate to the hub while jumping", stand, { 10, ERASURE_FLOOR }, { 9, LANDING })
		carriedJump(who .. ", portal to the Battleground's camp while jumping", stand, { 0, 0 }, { 1441, LANDING })
		case({
			Name = who .. ": portal round trip, hub to the arena and back, jumping each time",
			Seconds = 9,
			Latency = 0.15,
			Stand = stand,
			Floors = WORLD,
			Walk = walk(16),
			Jumps = { 1.9, 5.9 },
			DoubleJumps = { 2.3, 6.3 },
			Teleports = { { 2, 0, ERASURE_PAD }, { 6, 9, LANDING } },
			KeepsMomentum = true,
		}, "silent")
	end
end)

describe("MovementScenarios: cheats, the arrival's own rise (in-game review)", function()
	-- The rise a pad arrival allows is a jump and a double jump over where the pad put the body, and only until it
	-- lands: neither lets a client climb on.
	for _, avatar in ipairs(AVATARS) do
		local name, stand = avatar[1] :: string, avatar[2] :: number
		case({
			Name = ("%s avatar (%.2f): arrives on a pad and climbs 25 over it at 12 studs/s"):format(name, stand),
			Seconds = 8,
			Latency = 0.1,
			RemotesAlways = true,
			Stand = stand,
			Floors = WORLD,
			Teleports = { { 2, 0, ERASURE_PAD } },
			Cheat = function(t: number): (number?, number?)
				return nil, if t >= 2.2 then ERASURE_PAD + math.min(25, 12 * (t - 2.2)) else nil
			end,
		}, "strike")
		case({
			Name = ("%s avatar (%.2f): lands after a pad drop, then climbs 16 over its standing height"):format(
				name,
				stand
			),
			Seconds = 8,
			Latency = 0.1,
			RemotesAlways = true,
			Stand = stand,
			Floors = WORLD,
			Teleports = { { 2, 0, ERASURE_PAD } },
			Cheat = function(t: number): (number?, number?)
				return nil, if t >= 4 then ERASURE_FLOOR + stand + math.min(16, 12 * (t - 4)) else nil
			end,
		}, "strike")
	end
end)

describe("MovementScenarios: honest, a fall off the Erasure's arena brought home (K2)", function()
	-- WorldBossService takes a participant whose root passed under the underside of the arena's floor (the slab is 4
	-- studs thick) back to the hub: it sees the body a way late and acts on its next tick (D-XXXc). The audit follows
	-- the walk off the edge, the fall and the pivot mid-air, whatever the body's height, its round trip and whether it
	-- keeps its fall across the pivot.
	local EDGE = 60
	local START = 40
	local GRAVITY = 196.2
	local TICK = 1 / 20
	for _, avatar in ipairs(AVATARS) do
		local name, stand = avatar[1] :: string, avatar[2] :: number
		for _, L in ipairs({ 0.05, 0.2, 0.45 }) do
			for _, keeps in ipairs({ false, true }) do
				local crossing = (EDGE - START) / 16 + math.sqrt(2 * (stand + 4) / GRAVITY)
				case({
					Name = ("%s avatar (%.2f): walks off the Erasure's arena, brought home, L=%.2f%s"):format(
						name,
						stand,
						L,
						if keeps then ", keeps its fall" else ""
					),
					Seconds = 6,
					Latency = L,
					Stand = stand,
					Floors = WORLD,
					StartX = START,
					StartY = ERASURE_FLOOR + stand,
					Walk = walk(16),
					Teleports = { { crossing + L + TICK, 9, LANDING } },
					KeepsMomentum = keeps,
				}, "silent")
			end
		end
	end
end)
