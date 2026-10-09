# La Page (the 700-stud Battleground) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 170-stud PvE Battleground (D-131) with a 700 × 700 page where every member may hurt every other and the Forgers, behind a 3 s arrival bubble that bursts on attack, with player kills paid once per pair per 300 s under the Forgers' daily Folio cap (D-282).

**Architecture:** The page stays data (`BattlegroundConfig.Map`) turned into parts by the pure `BattlegroundLayout` and built by `BattlegroundService/Map`. The layout learns three shapes (block, wedge, cylinder) and a yaw; every obstacle becomes an oriented ground print, so the Forgers' 20-stud waypoint grid walks around turned pieces exactly. PvP reuses the zone system (`ZoneConfig` + `CombatService.claimZone`); the bubble reuses `SpawnProtectedUntil` through a new `CombatService.protect`; player-kill pay reuses `DailyCap` (the Forgers' profile counter) and the Flyleaf's pair ledger (`FlyleafRules.recordKill` with one paid death per window).

**Tech Stack:** Luau (`--!strict`), Rojo, Lune tests (`tests/run.luau`, `tests/harness.luau`, the pretend server in `tests/server.luau`), StyLua, Selene, luau-lsp.

**Spec:** `docs/superpowers/specs/2026-10-09-battleground-page-design.md` (layout reference: `docs/world/battleground/ref-2.jpg`).

## Global Constraints

- Luau, `--!strict` on every file touched under `src/shared` and every pure module; identifiers and comments in English; docs stay in French.
- Pure modules (`src/server/Pure/BattlegroundLayout.luau`, `FlyleafRules`, `DailyCap`): no `require`, no Roblox global. `BattlegroundLayout` stays in `src/server/Pure` (only the server requires it).
- Config only in `src/shared/Config/*` (`BattlegroundConfig`, `ZoneConfig`, `WorldConfig`) and `src/server/Config/AnalyticsConfig.luau`; no magic number in a service.
- Every player-visible text goes through `Strings.t`; a changed string means `lune run scripts/export-strings` regenerates `localization.csv`.
- `task.*` only; no per-player loop: everything runs from `BattlegroundService`'s existing Heartbeat accumulator.
- Damage only through `CombatService.ApplyDamage`; trust only the server's positions; every `pcall` path logs (`log.try`).
- No `TODO`, `FIXME`, placeholder, empty function or dead config.
- The spec's numbers: page `Size = 700` at `Origin = { 1500, 0, 0 }`; at most `MaxMembers = 12`; part budget 1500; no corridor under 16 studs between pieces on the ground; 12 edge arrivals (`Arrival_7..18`) at least 80 studs apart and at least 40 from every Forger spawn (kept at 60, `MinSpawnDistanceStuds`); Forger grid step 20; `ArrivalProtectionSeconds = 3`; `PlayerKill.PairCooldownSeconds = 300`; effects broadcast radius stays 250; streaming stays off.
- Setup once per worktree: if `Packages/` or `globalTypes.d.luau` is missing, run `./scripts/setup.sh` (the pretend-server specs need `Packages/Trove`).
- The test runner has no filter: `lune run tests/run` loads every `tests/**/*.spec.luau`. Read only the failures with `lune run tests/run 2>&1 | grep -E "✖|passed|failed to load" -A1`.
- Quality gates, all green before each commit: `scripts/check.sh` (StyLua check, Selene, luau-lsp analyze, Lune tests, strings, `localization.csv`, rojo build, the built place). Run `stylua src tests` first: the plan's code is written compact and StyLua lays it out.
- Conventional Commits, one commit per task (Task 3 adds a docs commit), each ending with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Branch `feat/battleground-page`; never commit on `main`.

## Review Focus

1. **A bubble that never bursts.** A respawned body still wears the hub SpawnLocation's `ForceField`, and `isSpawnProtected` reads any `ForceField` as protection no blow can drop, so the wearer stays invulnerable while hitting. Test: "take the hub's ForceField off a body the bubble replaces, and keep the hub's protection whole" (Task 2, `tests/DamageZones.spec.luau`).
2. **A protected player who hits without bursting, or who cannot hit at all.** The old rule refuses a protected attacker's blow; the bubble must let it land and burst at once. Test: "hold every blow off a bubble's wearer until it runs out or they strike, and burst it on their blow" (Task 2, `tests/DamageZones.spec.luau`).
3. **A member on the 60-stud cliffs dropped from the page.** `Context.insideBounds` lets go of a trusted position above `BoundsHeightStuds`, which was 60, the old wall height. Test: "hold a member jumping off the highest landing on the page" (Task 1, `tests/BattlegroundLayout.spec.luau`).
4. **A Forger that walks off the torn edge.** The walls are gone, and a Forger chasing someone on the deckle walked straight to its goal. Test: "pushes a goal out across its open edges and keeps every goal inside the roam" (Task 1, `tests/BattlegroundLayout.spec.luau`).
5. **A refused kill that still counts toward the pair, or a victim who walked home paying anyway.** A kill under the bubble, or by or of someone the page no longer holds, must neither pay nor start the pair's 300 s. Test: "pays nothing under a bubble, nor for a killer or a victim the page does not hold, nor for oneself" (Task 3, `tests/Battleground.spec.luau`).

## Files

| File | Task | Change |
|---|---|---|
| `src/shared/Config/BattlegroundConfig.luau` | 1, 2, 3 | new `Map`; `Pits.FirstX`/`WallThickness`; `BoundsHeightStuds`; `ArrivalProtectionSeconds`; `PlayerKill` |
| `src/server/Pure/BattlegroundLayout.luau` | 1 | shapes, yaw, oriented prints, deckle, ruling, dais, landmarks, `Roam`, `clampGoal` |
| `src/shared/Config/WorldConfig.luau` | 1 | `WorldConfig.Battleground` roles |
| `src/server/Services/BattlegroundService/Map.luau` | 1 | wedges, cylinders, yaw; markers face the centre |
| `src/server/Services/BattlegroundService/Motion.luau` | 1 | `clampGoal` |
| `src/server/Services/BattlegroundService/Pits.luau` | 1 | `PITS.WallThickness` |
| `src/shared/Config/ZoneConfig.luau` | 2 | `Battleground` zone |
| `src/server/Services/CombatService.luau` | 2 | `protect`, `isProtected`, the bubble's burst |
| `src/server/Services/BattlegroundService/{Context,Roster,init}.luau` | 2, 3 | zone claim, bubble on admit, `Roster.holds`, player kills, prune |
| `src/server/Services/BattlegroundService/Rewards.luau` | 3 | `payPlayer`, `prune`, shared `payFolios` |
| `src/server/Config/AnalyticsConfig.luau`, `src/shared/Strings.luau`, `localization.csv` | 3 | `BattlegroundKill`; cap toast wording |
| `tests/BattlegroundLayout.spec.luau` | 1 | rewritten |
| `tests/{SparPits,MovementGates,Config}.spec.luau` | 1, 2 | follow the removed walls; `protect` stub |
| `tests/DamageZones.spec.luau` | 2 | the zone and the bubble on the real `CombatService` |
| `tests/Battleground.spec.luau` | 2, 3 | source gates; `Rewards` on a pretend server |
| `tests/EconomyEvents.spec.luau` | 3 | the new reason |
| `docs/GAME_DESIGN.md`, `docs/ECONOMY.md`, `docs/DECISIONS.md`, `docs/PROGRESS.md` | 3 | D-282 |

Left out on purpose: a visible bubble (no `ForceField` drawn), lock-on onto other members (the Flyleaf's `MemberAttribute` pattern), a toast for an unpaid repeat kill, spawn choice by distance (arrivals stay taken in turn). Each is one small change once QA asks.

---

### Task 1: The 700-stud page, its landmarks and the Forgers' 20-stud grid

**Files:**
- Modify: `src/shared/Config/BattlegroundConfig.luau` (lines 1-80, the `Pits` block, `BoundsHeightStuds`)
- Modify (full rewrite): `src/server/Pure/BattlegroundLayout.luau`
- Modify: `src/shared/Config/WorldConfig.luau` (the `WorldConfig.Battleground` block, lines 192-210)
- Modify: `src/server/Services/BattlegroundService/Map.luau`, `Motion.luau` (`walkTo`), `Pits.luau` (`buildPit`)
- Test (full rewrite): `tests/BattlegroundLayout.spec.luau`
- Test (follow-ups): `tests/SparPits.spec.luau`, `tests/MovementGates.spec.luau`, `tests/Config.spec.luau`

**Interfaces:**
- Consumes: `BotConfig.Path.RadiusStuds` (2.5), `BotConfig.Reach.SightHeightStuds` (1.5), `WorldConfig.Ladder.{Rule,Training}`, `WorldConfig.FlatThicknessStuds`, `GameConfig.Movement.{JumpPower,DoubleJumpVelocity}`, `tests/gate.luau` `Gate.corners`.
- Produces:
  - `BattlegroundLayout` types `Shape = "Block" | "Wedge" | "Cylinder"`, `Piece`, `Mark`, `Print = { X, Z, HalfX, HalfZ, Cos, Sin }`; `Box` gains `Shape: Shape` and `Yaw: number` (degrees, the engine's `CFrame.Angles(0, rad(Yaw), 0)`); `Dressing` loses `WallRuleStuds` and `WallRuleProudStuds`; `Layout` gains `Roam: Rect`, and `Obstacles`/`Blocked` become `{ Print }`.
  - `BattlegroundLayout.printOf(box: Box): Print`, `grow(print: Print, by: number): Print`, `inPrint(print: Print, x: number, z: number): boolean`, `corners(print: Print): { Point }`.
  - `BattlegroundLayout.clampGoal(layout: Layout, x: number, z: number): (number, number)` replaces `clampOutOfCamp` (its only caller is `Motion.walkTo`).
  - `BattlegroundConfig.Map` fields read by the layout (`Deckle`, `RuleSpacingStuds`, `MarginX`, `Dais`, `Covers`, `Pieces`, `Plume`, `Crater`, `Bed`, `Marks`, `ArrivalSpacingStuds`, `PartBudget`); `Map.WallHeight`, `Map.WallThickness`, `Map.Pillars`, `Map.Stele`, `Map.RuleInsetStuds` are gone; `BattlegroundConfig.Pits.WallThickness = 2`, `Pits.FirstX = 650`; `BattlegroundConfig.BoundsHeightStuds = 80`.
  - `WorldConfig.Battleground` roles: `Floor`, `Rule`, `Trim`, `Dais`, `Cover`, `Landmark`, `Bed`, `Camp`, `CampLine`, `KillZone`, `Marker`, plus `CampTransparency`.

- [ ] **Step 1: Write the failing layout spec**

Replace the whole of `tests/BattlegroundLayout.spec.luau` with:

```lua
--!strict
-- The Battleground's page (D-131, D-282), held to what its config claims: 700 studs, every part on it and within the
-- part budget, nothing solid in the camp, on an arrival or on top of another solid, no corridor narrower than 16
-- studs, every arrival apart from every other and from the Forgers' spawns, a waypoint graph that is whole -- the
-- crater and the book's valley included -- and whose paths are clear and shortest, and a page that stands out of
-- the hub's sight and out of its packets' reach.
local BattlegroundConfig = require("../src/shared/Config/BattlegroundConfig")
local BattlegroundLayout = require("../src/server/Pure/BattlegroundLayout")
local BotConfig = require("../src/shared/Config/BotConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local Gate = require("./gate")
local Harness = require("./harness")
local LightingConfig = require("../src/shared/Config/LightingConfig")
local PortalConfig = require("../src/shared/Config/PortalConfig")
local WorldConfig = require("../src/shared/Config/WorldConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local MAP = BattlegroundConfig.Map
local DRESSING: BattlegroundLayout.Dressing = {
	FloorName = BattlegroundConfig.Anchors.Floor,
	KillZoneName = BattlegroundConfig.Anchors.KillZone,
	FlatThickness = WorldConfig.FlatThicknessStuds,
	RuleTop = WorldConfig.Ladder.Rule,
	CampTop = WorldConfig.Ladder.Training,
	CampTransparency = WorldConfig.Battleground.CampTransparency,
}
local LAYOUT = BattlegroundLayout.build(MAP, DRESSING, BotConfig.Path.RadiusStuds)
-- The engine's default gravity, which the place keeps (tests/LockOn.spec.luau).
local GRAVITY = 196.2
local EPSILON = 1e-6
local HUB = "src/server/Services/HubService.luau"
-- What World/PortalGate builds of the gate home: two discs, two posts, the lintel, the panel, the sign, the seal.
local GATE_PARTS = 8
-- The narrowest way between two pieces on the ground (D-282).
local CORRIDOR_STUDS = 16

local function overlaps(a: BattlegroundLayout.Box, b: BattlegroundLayout.Box): boolean
	for _, axis in ipairs({ { "X", "SizeX" }, { "Y", "SizeY" }, { "Z", "SizeZ" } }) do
		local centre, size = axis[1], axis[2]
		local gap = math.abs((a :: any)[centre] - (b :: any)[centre])
		if gap >= ((a :: any)[size] + (b :: any)[size]) / 2 - EPSILON then
			return false
		end
	end
	return true
end

local function blocked(x: number, z: number): boolean
	for _, print in ipairs(LAYOUT.Blocked) do
		if BattlegroundLayout.inPrint(print, x, z) then
			return true
		end
	end
	return false
end

local function distance(a: BattlegroundLayout.Point, b: BattlegroundLayout.Point): number
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

-- The distance from p to the segment a -> b.
local function toSegment(p: BattlegroundLayout.Point, a: BattlegroundLayout.Point, b: BattlegroundLayout.Point): number
	local dx, dz = b.X - a.X, b.Z - a.Z
	local t = math.clamp(((p.X - a.X) * dx + (p.Z - a.Z) * dz) / (dx * dx + dz * dz), 0, 1)
	return distance(p, { X = a.X + t * dx, Z = a.Z + t * dz })
end

-- The gap between two prints on the ground: 0 when they touch or overlap, else the shortest distance between them.
local function gap(a: BattlegroundLayout.Print, b: BattlegroundLayout.Print): number
	local ca, cb = BattlegroundLayout.corners(a), BattlegroundLayout.corners(b)
	for _, corner in ipairs(ca) do
		if BattlegroundLayout.inPrint(b, corner.X, corner.Z) then
			return 0
		end
	end
	for _, corner in ipairs(cb) do
		if BattlegroundLayout.inPrint(a, corner.X, corner.Z) then
			return 0
		end
	end
	local shortest = math.huge
	for index = 1, 4 do
		local a1, a2 = ca[index], ca[index % 4 + 1]
		local b1, b2 = cb[index], cb[index % 4 + 1]
		for _, corner in ipairs(cb) do
			shortest = math.min(shortest, toSegment(corner, a1, a2))
		end
		for _, corner in ipairs(ca) do
			shortest = math.min(shortest, toSegment(corner, b1, b2))
		end
	end
	return shortest
end

-- A number from HubService, which needs an engine to require.
local function hubNumber(name: string): number
	local value = string.match(fs.readFile(HUB), "\nlocal " .. name .. " = (%d+)\n")
	if value == nil then
		error(("%s has no numeric %s: this gate would check nothing"):format(HUB, name))
	end
	return tonumber(value) :: number
end

-- The shortest walk over the graph by Dijkstra, independent of the A* under test.
local function shortest(from: number, to: number): number
	local best: { [number]: number } = { [from] = 0 }
	local done: { [number]: boolean } = {}
	while true do
		local current, currentCost = nil, math.huge
		for index, cost in pairs(best) do
			if not done[index] and cost < currentCost then
				current, currentCost = index, cost
			end
		end
		if current == nil then
			return math.huge
		end
		if current == to then
			return currentCost
		end
		done[current] = true
		for _, neighbour in ipairs(LAYOUT.Edges[current]) do
			local cost = currentCost + distance(LAYOUT.Nodes[current], LAYOUT.Nodes[neighbour])
			if best[neighbour] == nil or cost < best[neighbour] then
				best[neighbour] = cost
			end
		end
	end
end

-- The arrivals in the camp, and the others.
local function arrivals(): ({ BattlegroundLayout.Point }, { BattlegroundLayout.Point })
	local camp, edge = {}, {}
	for _, arrival in ipairs(LAYOUT.Arrivals) do
		table.insert(if BattlegroundLayout.inRect(LAYOUT.Camp, arrival.X, arrival.Z) then camp else edge, arrival)
	end
	return camp, edge
end

describe("the Battleground's parts", function()
	it("make a 700-stud page, every one of them on it, the whole map within the part budget", function()
		expect(MAP.Size).toBe(700)
		local half = MAP.Size / 2
		local top = 0
		for _, box in ipairs(LAYOUT.Boxes) do
			if box.Role ~= "KillZone" then
				for _, corner in ipairs(BattlegroundLayout.corners(BattlegroundLayout.printOf(box))) do
					if math.abs(corner.X) > half + EPSILON or math.abs(corner.Z) > half + EPSILON then
						error(("%s leaves the page"):format(box.Name))
					end
				end
				expect(box.Y - box.SizeY / 2).toBeGreaterThanOrEqual(-MAP.FloorThickness - EPSILON)
				top = math.max(top, box.Y + box.SizeY / 2)
			end
		end
		local parts = #LAYOUT.Boxes + #LAYOUT.Arrivals + #LAYOUT.BotSpawns + GATE_PARTS
		expect(parts).toBeLessThanOrEqual(MAP.PartBudget)
		-- The highest landing is the cliffs' 60 studs.
		expect(top).toBe(60)
		for _, tear in ipairs(MAP.Deckle.Tears) do
			expect(tear).toBeGreaterThanOrEqual(0)
			expect(tear).toBeLessThan(MAP.Deckle.BandStuds)
		end
	end)

	it("draw everything flat on a rung of the ladder, sunk into the floor", function()
		local rungs = {
			Rule = WorldConfig.Ladder.Rule,
			CampLine = WorldConfig.Ladder.Rule,
			Camp = WorldConfig.Ladder.Training,
			Bed = WorldConfig.Ladder.Training,
		}
		local count = 0
		for _, box in ipairs(LAYOUT.Boxes) do
			local rung = rungs[box.Role]
			if rung ~= nil then
				count += 1
				expect(box.Y + box.SizeY / 2).toBeCloseTo(rung, 9)
				expect(box.Y - box.SizeY / 2).toBeLessThan(0)
				expect(box.Solid).toBe(false)
			end
			-- Ink drawn on a raised top touches nothing either.
			if box.Role == "Trim" then
				expect(box.Solid).toBe(false)
			end
		end
		expect(count).toBeGreaterThan(30)
	end)

	it("never put one unturned solid inside another", function()
		local solids: { BattlegroundLayout.Box } = {}
		for _, box in ipairs(LAYOUT.Boxes) do
			if box.Solid and box.Yaw == 0 then
				table.insert(solids, box)
			end
		end
		for first = 1, #solids do
			for second = first + 1, #solids do
				if overlaps(solids[first], solids[second]) then
					error(("%s overlaps %s"):format(solids[first].Name, solids[second].Name))
				end
			end
		end
	end)

	it("leave no corridor narrower than 16 studs between two pieces on the ground", function()
		-- Pieces that touch are one mass (a ring, a stack, an arch); a corridor is the way between two masses.
		local obstacles = LAYOUT.Obstacles
		expect(#obstacles).toBeGreaterThan(50)
		local gaps: { { number } } = {}
		local mass: { number } = {}
		for first = 1, #obstacles do
			gaps[first] = {}
			for second = 1, #obstacles do
				gaps[first][second] = if first == second then 0 else gap(obstacles[first], obstacles[second])
			end
		end
		for start = 1, #obstacles do
			if mass[start] == nil then
				mass[start] = start
				local queue = { start }
				while #queue > 0 do
					local current = table.remove(queue) :: number
					for other = 1, #obstacles do
						if mass[other] == nil and gaps[current][other] <= EPSILON then
							mass[other] = start
							table.insert(queue, other)
						end
					end
				end
			end
		end
		for first = 1, #obstacles do
			for second = first + 1, #obstacles do
				local apart = gaps[first][second]
				if mass[first] ~= mass[second] and apart < CORRIDOR_STUDS then
					local a, b = obstacles[first], obstacles[second]
					error(
						("a %.1f-stud corridor between the pieces at (%d, %d) and (%d, %d)"):format(
							apart,
							a.X,
							a.Z,
							b.X,
							b.Z
						)
					)
				end
			end
		end
	end)

	it("leave the camp free of anything solid", function()
		local camp = BattlegroundLayout.inflate(LAYOUT.Camp, 0)
		for _, obstacle in ipairs(LAYOUT.Obstacles) do
			for _, corner in ipairs(BattlegroundLayout.corners(obstacle)) do
				expect(BattlegroundLayout.inRect(camp, corner.X, corner.Z)).toBe(false)
			end
		end
	end)

	it("are each painted a role the world has", function()
		for _, box in ipairs(LAYOUT.Boxes) do
			local role = (WorldConfig.Battleground :: any)[box.Role]
			if type(role) ~= "string" or WorldConfig.Colors[role] == nil then
				error(("%s is drawn as %s, which WorldConfig.Battleground does not paint"):format(box.Name, box.Role))
			end
		end
	end)

	it("hold a member jumping off the highest landing on the page", function()
		local movement = GameConfig.Movement
		local reach = (movement.JumpPower ^ 2 + movement.DoubleJumpVelocity ^ 2) / (2 * GRAVITY)
		local highest = 0
		for _, box in ipairs(LAYOUT.Boxes) do
			if box.Solid then
				highest = math.max(highest, box.Y + box.SizeY / 2)
			end
		end
		expect(BattlegroundConfig.BoundsHeightStuds).toBeGreaterThan(
			highest + BattlegroundConfig.StandingRootStuds + reach
		)
		-- The low walls on the dais hide a Forger's quarry, standing on the dais or not.
		expect(MAP.CoverHeight).toBeGreaterThan(BattlegroundConfig.StandingRootStuds + BotConfig.Reach.SightHeightStuds)
	end)
end)

describe("the arrivals", function()
	it("are six in the camp with the return gate, and twelve round the edge", function()
		local camp, edge = arrivals()
		expect(#camp).toBe(6)
		expect(#edge).toBe(12)
		expect(BattlegroundLayout.inRect(LAYOUT.Camp, LAYOUT.ReturnGate.X, LAYOUT.ReturnGate.Z)).toBe(true)
	end)

	it("stand 80 studs apart round the edge, 60 from every Forger's spawn, on nothing solid", function()
		local camp, edge = arrivals()
		for index, arrival in ipairs(edge) do
			for other = index + 1, #edge do
				expect(distance(arrival, edge[other])).toBeGreaterThanOrEqual(MAP.ArrivalSpacingStuds)
			end
			for _, inCamp in ipairs(camp) do
				expect(distance(arrival, inCamp)).toBeGreaterThanOrEqual(MAP.ArrivalSpacingStuds)
			end
		end
		for _, arrival in ipairs(LAYOUT.Arrivals) do
			for _, spawn in ipairs(LAYOUT.BotSpawns) do
				expect(distance(arrival, spawn)).toBeGreaterThanOrEqual(MAP.MinSpawnDistanceStuds)
			end
			for _, obstacle in ipairs(LAYOUT.Obstacles) do
				expect(
					BattlegroundLayout.inPrint(
						BattlegroundLayout.grow(obstacle, LAYOUT.PathRadius),
						arrival.X,
						arrival.Z
					)
				).toBe(false)
			end
			expect(BattlegroundLayout.inRect(LAYOUT.Bounds, arrival.X, arrival.Z)).toBe(true)
		end
		expect(MAP.MinSpawnDistanceStuds).toBeGreaterThanOrEqual(40)
	end)

	it("land nobody in the circle that sends them home", function()
		for _, arrival in ipairs(LAYOUT.Arrivals) do
			expect(distance(arrival, LAYOUT.ReturnGate)).toBeGreaterThanOrEqual(PortalConfig.ZoneRadiusStuds + 2)
		end
	end)
end)

describe("the camp", function()
	it("holds the whole return gate, its back flush on the camp's west edge", function()
		-- The gate faces east, into the page.
		local corners = Gate.corners(LAYOUT.ReturnGate.X, LAYOUT.ReturnGate.Z, 1, 0)
		local westmost = math.huge
		for _, corner in ipairs(corners) do
			expect(BattlegroundLayout.inRect(LAYOUT.Camp, corner[1], corner[2])).toBe(true)
			westmost = math.min(westmost, corner[1])
		end
		expect(westmost).toBeCloseTo(LAYOUT.Camp.MinX, 9)
	end)

	it("lets a Forger walk straight up to the edge a goal is pushed onto, and not a hair past it", function()
		local x, z = BattlegroundLayout.clampGoal(LAYOUT, -315, LAYOUT.Camp.MinZ + 2)
		expect(BattlegroundLayout.segmentClear(LAYOUT, x, z - 15, x, z)).toBe(true)
		expect(BattlegroundLayout.segmentClear(LAYOUT, x, z - 15, x, z + 0.1)).toBe(false)
		x, z = BattlegroundLayout.clampGoal(LAYOUT, -315, 0)
		expect(BattlegroundLayout.segmentClear(LAYOUT, x + 15, z, x, z)).toBe(true)
		expect(BattlegroundLayout.segmentClear(LAYOUT, x + 15, z, x - 0.1, z)).toBe(false)
	end)

	it("pushes a goal out across its open edges and keeps every goal inside the roam", function()
		local radius = LAYOUT.PathRadius
		local x, z = BattlegroundLayout.clampGoal(LAYOUT, -315, 0)
		expect(x).toBe(LAYOUT.Camp.MaxX + radius)
		expect(z).toBe(0)
		x, z = BattlegroundLayout.clampGoal(LAYOUT, -315, LAYOUT.Camp.MinZ + 2)
		expect(x).toBe(-315)
		expect(z).toBe(LAYOUT.Camp.MinZ - radius)
		-- Behind the camp, toward the torn edge: brought into the roam first, then out of the camp eastward.
		x, z = BattlegroundLayout.clampGoal(LAYOUT, LAYOUT.Camp.MinX + 1, 0)
		expect(x).toBe(LAYOUT.Camp.MaxX + radius)
		expect(z).toBe(0)
		-- A goal on the torn edge is brought back to the roam's border.
		x, z = BattlegroundLayout.clampGoal(LAYOUT, 345, -348)
		expect(x).toBe(LAYOUT.Roam.MaxX)
		expect(z).toBe(LAYOUT.Roam.MinZ)
		-- A goal inside the roam and outside the camp is left where it is.
		x, z = BattlegroundLayout.clampGoal(LAYOUT, 10, -20)
		expect(x).toBe(10)
		expect(z).toBe(-20)
	end)
end)

describe("the Forgers' ground", function()
	it("spawns them in the roam, clear of every obstacle and of the camp", function()
		for _, spawn in ipairs(LAYOUT.BotSpawns) do
			expect(blocked(spawn.X, spawn.Z)).toBe(false)
			expect(BattlegroundLayout.inRect(LAYOUT.Roam, spawn.X, spawn.Z)).toBe(true)
		end
	end)

	it("lays no waypoint in the camp or an obstacle, nor past the roam", function()
		expect(#LAYOUT.Nodes).toBeGreaterThan(800)
		for _, node in ipairs(LAYOUT.Nodes) do
			expect(blocked(node.X, node.Z)).toBe(false)
			expect(BattlegroundLayout.inRect(LAYOUT.Camp, node.X, node.Z)).toBe(false)
			expect(BattlegroundLayout.inRect(LAYOUT.Roam, node.X, node.Z)).toBe(true)
		end
	end)

	it("joins every waypoint to every other, the crater's floor and the book's valley included", function()
		local seen: { [number]: boolean } = { [1] = true }
		local queue = { 1 }
		local count = 1
		while #queue > 0 do
			local current = table.remove(queue, 1) :: number
			for _, neighbour in ipairs(LAYOUT.Edges[current]) do
				if not seen[neighbour] then
					seen[neighbour] = true
					count += 1
					table.insert(queue, neighbour)
				end
			end
		end
		expect(count).toBe(#LAYOUT.Nodes)
		-- Each enclosed ground has a waypoint of its own, walked to straight from its middle.
		for _, inside in ipairs({ { X = MAP.Crater.X, Z = MAP.Crater.Z }, { X = -200, Z = -220 } }) do
			local node = LAYOUT.Nodes[BattlegroundLayout.nearestNode(LAYOUT, inside.X, inside.Z) :: number]
			expect(distance(node, inside)).toBeLessThan(MAP.Grid.StepStuds)
			expect(BattlegroundLayout.segmentClear(LAYOUT, inside.X, inside.Z, node.X, node.Z)).toBe(true)
		end
	end)

	it("finds the shortest path, every leg of it a clear straight walk", function()
		local ends: { number } = {
			BattlegroundLayout.nearestNode(LAYOUT, MAP.Crater.X, MAP.Crater.Z) :: number,
			BattlegroundLayout.nearestNode(LAYOUT, LAYOUT.Camp.MaxX + 5, 0) :: number,
			BattlegroundLayout.nearestNode(LAYOUT, 250, 150) :: number,
			#LAYOUT.Nodes,
		}
		for _, from in ipairs(ends) do
			for _, to in ipairs(ends) do
				local route = BattlegroundLayout.path(LAYOUT, from, to)
				if route == nil then
					error(("no path from node %d to node %d"):format(from, to))
				end
				expect(route[1]).toBe(from)
				expect(route[#route]).toBe(to)
				local length = 0
				for index = 2, #route do
					local a, b = LAYOUT.Nodes[route[index - 1]], LAYOUT.Nodes[route[index]]
					expect(BattlegroundLayout.segmentClear(LAYOUT, a.X, a.Z, b.X, b.Z)).toBe(true)
					length += distance(a, b)
				end
				expect(length).toBeCloseTo(shortest(from, to), 6)
			end
		end
		-- Always the same path for the same ends.
		expect(BattlegroundLayout.path(LAYOUT, ends[1], ends[3])).toEqual(
			BattlegroundLayout.path(LAYOUT, ends[1], ends[3])
		)
	end)

	it("heads first for a waypoint it can walk to straight", function()
		for _, spawn in ipairs(LAYOUT.BotSpawns) do
			local node = LAYOUT.Nodes[BattlegroundLayout.nearestNode(LAYOUT, spawn.X, spawn.Z) :: number]
			expect(BattlegroundLayout.segmentClear(LAYOUT, spawn.X, spawn.Z, node.X, node.Z)).toBe(true)
		end
		-- Just south of the north wall on the dais, the nearest waypoint lies past its end, the way there cut by
		-- the wall: the Forger takes the nearest one it can reach instead of walking into it.
		local x, z = 5, -60 + 1 + LAYOUT.PathRadius + 0.3
		local nearest, nearestDistance = 0, math.huge
		for index, node in ipairs(LAYOUT.Nodes) do
			local apart = distance(node, { X = x, Z = z })
			if apart < nearestDistance then
				nearest, nearestDistance = index, apart
			end
		end
		local behind = LAYOUT.Nodes[nearest]
		expect(BattlegroundLayout.segmentClear(LAYOUT, x, z, behind.X, behind.Z)).toBe(false)
		local chosen = BattlegroundLayout.nearestNode(LAYOUT, x, z) :: number
		expect(chosen ~= nearest).toBe(true)
		expect(BattlegroundLayout.segmentClear(LAYOUT, x, z, LAYOUT.Nodes[chosen].X, LAYOUT.Nodes[chosen].Z)).toBe(true)
	end)

	it("breaks a tie between two equal walks toward the lower node, so every Forger takes the same one", function()
		-- A square with no diagonals: 1 -> 2 -> 4 and 1 -> 3 -> 4 are the same length.
		local square = {
			Nodes = { { X = 0, Z = 0 }, { X = 10, Z = 0 }, { X = 0, Z = 10 }, { X = 10, Z = 10 } },
			Edges = { { 2, 3 }, { 1, 4 }, { 1, 4 }, { 2, 3 } },
		}
		expect(BattlegroundLayout.path(square :: any, 1, 4)).toEqual({ 1, 2, 4 })
		expect(BattlegroundLayout.path(square :: any, 4, 1)).toEqual({ 4, 2, 1 })
	end)

	it("is blocked across the quill's turned stem and by the camp, and open beside the stem and down a lane", function()
		local plume = MAP.Plume
		local yaw = math.rad(plume.Yaw)
		-- Along the stem, and across it.
		local ax, az = math.sin(yaw), math.cos(yaw)
		local cx, cz = math.cos(yaw), -math.sin(yaw)
		local mx, mz = plume.X - ax * plume.TipLength / 2, plume.Z - az * plume.TipLength / 2
		expect(BattlegroundLayout.segmentClear(LAYOUT, mx - cx * 20, mz - cz * 20, mx + cx * 20, mz + cz * 20)).toBe(
			false
		)
		-- Twenty studs off its axis, alongside: inside the stem's square bounds, outside the stem.
		local sx, sz = mx + cx * 20, mz + cz * 20
		expect(BattlegroundLayout.segmentClear(LAYOUT, sx - ax * 50, sz - az * 50, sx + ax * 50, sz + az * 50)).toBe(
			true
		)
		expect(BattlegroundLayout.segmentClear(LAYOUT, -320, -40, -320, 40)).toBe(false)
		expect(BattlegroundLayout.segmentClear(LAYOUT, -30, -40, -30, 40)).toBe(true)
	end)
end)

describe("the Battleground's names", function()
	it("names every part a reader finds by name once, in the map and in the Workspace", function()
		local anchors = BattlegroundConfig.Anchors
		local prefixes = { anchors.Arrival, anchors.BotSpawn }
		local seen: { [string]: boolean } = {}
		local function claim(name: string)
			if seen[name] then
				error(("two parts of the Battleground are called %s"):format(name))
			end
			for _, prefix in ipairs(prefixes) do
				if string.sub(name, 1, #prefix) == prefix then
					error(("%s reads as one of the markers %s*"):format(name, prefix))
				end
			end
			seen[name] = true
		end
		for _, box in ipairs(LAYOUT.Boxes) do
			claim(box.Name)
		end
		-- The return gate stands inside the map, its seal and its sign inside the gate.
		claim(PortalConfig.Anchors.ReturnGate)
		claim(PortalConfig.Anchors.Seal)
		claim(PortalConfig.Anchors.Sign)
		expect(seen[anchors.Floor]).toBe(true)
		expect(seen[anchors.KillZone]).toBe(true)
		expect(string.sub(anchors.Arrival, 1, #anchors.BotSpawn) ~= anchors.BotSpawn).toBe(true)
		expect(string.sub(anchors.BotSpawn, 1, #anchors.Arrival) ~= anchors.Arrival).toBe(true)
		-- Each folder a service rebuilds at Start destroys whatever already bears its name.
		local workspace = { anchors.Map, BotConfig.FolderName, WorldConfig.HubAnchors.Folder }
		for first = 1, #workspace do
			for second = first + 1, #workspace do
				expect(workspace[first] ~= workspace[second]).toBe(true)
			end
		end
	end)
end)

describe("the Battleground's place in the world", function()
	it("stands out of the hub's sight and out of its packets' reach", function()
		-- The hub's outer edge: the platform and its kerb. The arenas stacked above x = z = 0 are narrower.
		local hubEdge = hubNumber("PLATFORM_SIZE_STUDS") / 2 + hubNumber("PLATFORM_EDGE_WIDTH_STUDS")
		local origin = MAP.Origin
		local toCentre = math.sqrt(origin[1] ^ 2 + origin[3] ^ 2)
		local apart = toCentre - MAP.Size / 2 - hubEdge
		expect(apart).toBeGreaterThanOrEqual(GameConfig.Vfx.BroadcastRadiusStuds)
		expect(apart).toBeGreaterThanOrEqual(LightingConfig.Lighting.Numbers.FogEnd)
		expect(origin[2]).toBe(0)
	end)

	it("kills below the floor well above the engine's own cutoff, under the whole page", function()
		expect(MAP.KillZoneDepth).toBeLessThan(-MAP.FloorThickness)
		expect(MAP.KillZoneDepth).toBeGreaterThan(-500)
		expect(MAP.KillZoneSpread).toBeGreaterThan(1)
		-- A Forger thrown through the floor is caught by its fall check first, with no credit.
		expect(BotConfig.FallMarginStuds).toBeLessThan(-MAP.KillZoneDepth)
	end)
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `lune run tests/run 2>&1 | grep -E "✖|passed|failed to load" -A1`
Expected: `✖ failed to load tests/BattlegroundLayout.spec.luau: ... src/server/Pure/BattlegroundLayout:152: attempt to perform arithmetic (div) on nil and number` (the old builder still reads `WallRuleProudStuds` and the walls).

- [ ] **Step 3: Implement the page**

3a. In `src/shared/Config/BattlegroundConfig.luau`, replace lines 1-80 (the header through the closing `}` of `BattlegroundConfig.Map`) with:

```lua
--!strict
-- The Battleground (D-131, D-282): one permanent page built in code far east of the hub, 700 studs a side, where
-- every member may hurt every other and the Forgers (BotConfig) come at all of them. Pure data.
--
-- Local frame: x is east, z is south, and y = 0 is the floor's top face. A world position is Map.Origin plus a
-- local one. The whole layout -- the floor and its torn edge, the ruling, the camp, the central place, the
-- landmarks, the arrivals, the waypoint grid -- is derived from Map by BattlegroundLayout, and
-- tests/BattlegroundLayout.spec.luau holds every claim the comments below make.

export type Point = { X: number, Z: number }
export type Rect = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
export type Shape = "Block" | "Wedge" | "Cylinder"
export type Cover = { Name: string, X: number, Z: number, SizeX: number, SizeZ: number }
-- A solid piece of a landmark: its footprint's centre, the height of its underside, its size (x, y, z) and its turn
-- about the vertical in degrees. A Wedge rises toward its own +z; a Cylinder stands on its flat face, its x and z
-- both the diameter.
export type Piece = {
	Name: string,
	Shape: Shape,
	X: number,
	Z: number,
	Base: number,
	Size: { number },
	Yaw: number?,
}
-- A mark drawn flat on a top face Base studs above the floor: ink that touches nothing, a Rule on the floor and a
-- Trim on anything raised.
export type Mark = {
	Name: string,
	Shape: Shape,
	X: number,
	Z: number,
	Base: number,
	SizeX: number,
	SizeZ: number,
	Yaw: number?,
}

local BattlegroundConfig = {}

BattlegroundConfig.Map = {
	-- The centre of the floor's top face: the page runs from x 1150 to 1850, past the fog (LightingConfig FogEnd)
	-- and every effect packet's reach (GameConfig.Vfx.BroadcastRadiusStuds) from the hub, clear of the arenas
	-- stacked above x = z = 0. A fight at one end of it is no longer sent to the other end (D-282).
	Origin = { 1500, 0, 0 },
	Size = 700,
	FloorThickness = 4,
	-- The kill plane: under the floor, far above the engine's FallenPartsDestroyHeight (-500), and wide enough that
	-- nothing thrown off an edge can miss it.
	KillZoneDepth = -40,
	KillZoneSpread = 1.5,
	KillZoneThickness = 1,
	-- The torn edge: a band this deep round the page, cut in SlotStuds tabs, each torn Tears[i] studs in from the
	-- edge, the tears taken in turn round the page. Every tear is shallower than the band.
	Deckle = { BandStuds = 10, SlotStuds = 20, Tears = { 0, 5, 8, 2, 6, 3, 7, 1, 4 } },
	-- The ruling, as on the hub: a line along x every RuleSpacingStuds, and the margin along z at MarginX.
	RuleSpacingStuds = 20,
	RuleWidthStuds = 0.6,
	MarginX = -300,
	-- The camp, at the west edge: where the first six arrivals are and the gate home stands, behind an ink line at
	-- its east edge. It protects nobody from another member (D-282); a Forger never enters it nor answers it.
	Camp = { MinX = -336, MaxX = -310, MinZ = -22, MaxZ = 22 } :: Rect,
	-- The gate back to the hub, facing east; its back posts end flush on the camp's west edge.
	ReturnGate = { X = -329.5, Z = 0 } :: Point,
	-- Where a player lands, taken in turn: six in the camp, more than the return circle's radius plus two studs
	-- from its seal, then twelve round the edge, ArrivalSpacingStuds apart from every other arrival.
	Arrivals = {
		{ X = -321, Z = -10 },
		{ X = -321, Z = 0 },
		{ X = -321, Z = 10 },
		{ X = -315, Z = -10 },
		{ X = -315, Z = 0 },
		{ X = -315, Z = 10 },
		{ X = -305, Z = -305 },
		{ X = -50, Z = -315 },
		{ X = 180, Z = -315 },
		{ X = 305, Z = -305 },
		{ X = 310, Z = -100 },
		{ X = 310, Z = 100 },
		{ X = 305, Z = 305 },
		{ X = 100, Z = 310 },
		{ X = -100, Z = 310 },
		{ X = -305, Z = 305 },
		{ X = -310, Z = 100 },
		{ X = -310, Z = -100 },
	} :: { Point },
	ArrivalSpacingStuds = 80,
	-- The central place: a dais one step high, which a Forger walks onto, edged in ink.
	Dais = { Size = 200, Height = 1 },
	-- Low walls on the dais. Over a Forger's eyes (StandingRootStuds + BotConfig.Reach.SightHeightStuds), so they
	-- hide whoever crouches behind them.
	CoverHeight = 6,
	Covers = {
		{ Name = "CoverNorth", X = 0, Z = -60, SizeX = 30, SizeZ = 2 },
		{ Name = "CoverSouth", X = 0, Z = 60, SizeX = 30, SizeZ = 2 },
		{ Name = "CoverWest", X = -60, Z = 0, SizeX = 2, SizeZ = 30 },
		{ Name = "CoverEast", X = 60, Z = 0, SizeX = 2, SizeZ = 30 },
		{ Name = "CoverNorthEastA", X = 60, Z = -70, SizeX = 20, SizeZ = 2 },
		{ Name = "CoverNorthEastB", X = 69, Z = -59, SizeX = 2, SizeZ = 20 },
		{ Name = "CoverNorthWestA", X = -60, Z = -70, SizeX = 20, SizeZ = 2 },
		{ Name = "CoverNorthWestB", X = -69, Z = -59, SizeX = 2, SizeZ = 20 },
		{ Name = "CoverSouthEastA", X = 60, Z = 70, SizeX = 20, SizeZ = 2 },
		{ Name = "CoverSouthEastB", X = 69, Z = 59, SizeX = 2, SizeZ = 20 },
		{ Name = "CoverSouthWestA", X = -60, Z = 70, SizeX = 20, SizeZ = 2 },
		{ Name = "CoverSouthWestB", X = -69, Z = 59, SizeX = 2, SizeZ = 20 },
	} :: { Cover },
	-- The landmarks a player climbs and a Forger walks around (it stays on the ground: what is high escapes it).
	Pieces = {
		-- The open book, north-west: two half-pages in three steps of six, rising to the spine, a 20-stud valley
		-- along it.
		{ Name = "BookLeft1", Shape = "Block", X = -250, Z = -220, Base = 0, Size = { 80, 6, 140 } },
		{ Name = "BookLeft2", Shape = "Block", X = -230, Z = -220, Base = 6, Size = { 40, 6, 140 } },
		{ Name = "BookLeft3", Shape = "Block", X = -220, Z = -220, Base = 12, Size = { 20, 6, 140 } },
		{ Name = "BookRight1", Shape = "Block", X = -150, Z = -220, Base = 0, Size = { 80, 6, 140 } },
		{ Name = "BookRight2", Shape = "Block", X = -170, Z = -220, Base = 6, Size = { 40, 6, 140 } },
		{ Name = "BookRight3", Shape = "Block", X = -180, Z = -220, Base = 12, Size = { 20, 6, 140 } },
		-- The folio cliffs, north-east: books stacked in landings of 15, 30, 45 and 60 studs, the highest point,
		-- each reached by a ramp rising east.
		{ Name = "Folio1", Shape = "Block", X = 230, Z = -220, Base = 0, Size = { 120, 15, 100 } },
		{ Name = "Folio2", Shape = "Block", X = 245, Z = -220, Base = 15, Size = { 90, 15, 80 } },
		{ Name = "Folio3", Shape = "Block", X = 260, Z = -220, Base = 30, Size = { 60, 15, 60 } },
		{ Name = "Folio4", Shape = "Block", X = 275, Z = -220, Base = 45, Size = { 30, 15, 40 } },
		{ Name = "FolioRamp1", Shape = "Wedge", X = 155, Z = -220, Base = 0, Size = { 12, 15, 30 }, Yaw = 90 },
		{ Name = "FolioRamp2", Shape = "Wedge", X = 185, Z = -220, Base = 15, Size = { 12, 15, 30 }, Yaw = 90 },
		{ Name = "FolioRamp3", Shape = "Wedge", X = 215, Z = -220, Base = 30, Size = { 12, 15, 30 }, Yaw = 90 },
		{ Name = "FolioRamp4", Shape = "Wedge", X = 245, Z = -220, Base = 45, Size = { 12, 15, 30 }, Yaw = 90 },
		-- The stitched bridge, east, over the ruled bed: a deck between two ramps.
		{ Name = "BridgeDeck", Shape = "Block", X = 240, Z = 30, Base = 0, Size = { 60, 4, 30 } },
		{ Name = "BridgeRampWest", Shape = "Wedge", X = 204, Z = 30, Base = 0, Size = { 30, 4, 12 }, Yaw = 90 },
		{ Name = "BridgeRampEast", Shape = "Wedge", X = 276, Z = 30, Base = 0, Size = { 30, 4, 12 }, Yaw = -90 },
		-- The field of seals, south: wax discs.
		{ Name = "Seal1", Shape = "Cylinder", X = -40, Z = 210, Base = 0, Size = { 24, 3, 24 } },
		{ Name = "Seal2", Shape = "Cylinder", X = 20, Z = 200, Base = 0, Size = { 16, 2, 16 } },
		{ Name = "Seal3", Shape = "Cylinder", X = 80, Z = 215, Base = 0, Size = { 30, 6, 30 } },
		{ Name = "Seal4", Shape = "Cylinder", X = 140, Z = 205, Base = 0, Size = { 20, 4, 20 } },
		{ Name = "Seal5", Shape = "Cylinder", X = -20, Z = 265, Base = 0, Size = { 28, 5, 28 } },
		{ Name = "Seal6", Shape = "Cylinder", X = 45, Z = 260, Base = 0, Size = { 18, 2, 18 } },
		{ Name = "Seal7", Shape = "Cylinder", X = 110, Z = 270, Base = 0, Size = { 24, 4, 24 } },
		{ Name = "Seal8", Shape = "Cylinder", X = 0, Z = 315, Base = 0, Size = { 20, 3, 20 } },
		{ Name = "Seal9", Shape = "Cylinder", X = 150, Z = 300, Base = 0, Size = { 22, 6, 22 } },
		-- The scriptorium's ruins, south-west: three arches (two piles and a lintel, 24 studs) and broken desks.
		{ Name = "Arch1West", Shape = "Block", X = -280, Z = 170, Base = 0, Size = { 4, 20, 4 } },
		{ Name = "Arch1East", Shape = "Block", X = -260, Z = 170, Base = 0, Size = { 4, 20, 4 } },
		{ Name = "Arch1Lintel", Shape = "Block", X = -270, Z = 170, Base = 20, Size = { 24, 4, 4 } },
		{ Name = "Arch2West", Shape = "Block", X = -200, Z = 190, Base = 0, Size = { 4, 20, 4 } },
		{ Name = "Arch2East", Shape = "Block", X = -180, Z = 190, Base = 0, Size = { 4, 20, 4 } },
		{ Name = "Arch2Lintel", Shape = "Block", X = -190, Z = 190, Base = 20, Size = { 24, 4, 4 } },
		{ Name = "Arch3West", Shape = "Block", X = -260, Z = 250, Base = 0, Size = { 4, 20, 4 } },
		{ Name = "Arch3East", Shape = "Block", X = -240, Z = 250, Base = 0, Size = { 4, 20, 4 } },
		{ Name = "Arch3Lintel", Shape = "Block", X = -250, Z = 250, Base = 20, Size = { 24, 4, 4 } },
		{ Name = "Desk1", Shape = "Block", X = -220, Z = 140, Base = 0, Size = { 8, 6, 6 }, Yaw = 20 },
		{ Name = "Desk2", Shape = "Block", X = -305, Z = 225, Base = 0, Size = { 6, 4, 8 }, Yaw = -15 },
		{ Name = "Desk3", Shape = "Block", X = -180, Z = 260, Base = 0, Size = { 8, 5, 8 }, Yaw = 35 },
	} :: { Piece },
	-- The fallen quill, north: a stem lying across the page from south-west to north-east, rising from the floor to
	-- Height along Length - TipLength, then a bevelled tip back down.
	Plume = { X = 60, Z = -240, Yaw = 135, Length = 180, TipLength = 20, Width = 24, Height = 40 },
	-- The inkwell's crater, west: a rim ring of Segments blocks, OuterRadius out and RimStuds thick, broken by four
	-- breaches of BreachSegments facing north, east, south and west.
	Crater = { X = -220, Z = -20, OuterRadius = 60, RimStuds = 6, Height = 6, Segments = 24, BreachSegments = 2 },
	-- The ruled bed, east: from the cliffs to the south edge, drawn flat with Lines ink lines along it (D-282: dug,
	-- it would put a member under the floor the page holds them to).
	Bed = { MinX = 220, MaxX = 260, MinZ = -170, MaxZ = 340, Lines = 3 },
	-- Ink drawn on the page: blots on the floor, and the bridge's cross stitches on its deck.
	Marks = {
		{ Name = "Blot1", Shape = "Cylinder", X = -70, Z = 245, Base = 0, SizeX = 14, SizeZ = 14 },
		{ Name = "Blot2", Shape = "Cylinder", X = 60, Z = 300, Base = 0, SizeX = 10, SizeZ = 10 },
		{ Name = "Blot3", Shape = "Cylinder", X = 180, Z = 240, Base = 0, SizeX = 12, SizeZ = 12 },
		{ Name = "Stitch1A", Shape = "Block", X = 225, Z = 30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = 45 },
		{ Name = "Stitch1B", Shape = "Block", X = 225, Z = 30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = -45 },
		{ Name = "Stitch2A", Shape = "Block", X = 240, Z = 30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = 45 },
		{ Name = "Stitch2B", Shape = "Block", X = 240, Z = 30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = -45 },
		{ Name = "Stitch3A", Shape = "Block", X = 255, Z = 30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = 45 },
		{ Name = "Stitch3B", Shape = "Block", X = 255, Z = 30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = -45 },
	} :: { Mark },
	-- Where a Forger appears: the one furthest from every player (BotBrain.pickSpawn), on open ground.
	BotSpawns = {
		{ X = 0, Z = -140 },
		{ X = 150, Z = -100 },
		{ X = 160, Z = 100 },
		{ X = 0, Z = 150 },
		{ X = -130, Z = 150 },
		{ X = -140, Z = -60 },
		{ X = -60, Z = -150 },
		{ X = 300, Z = 0 },
	} :: { Point },
	MinSpawnDistanceStuds = 60,
	-- The Forgers' waypoints: a node every StepStuds inside Size / 2 - MarginStuds (33 x 33 candidates), minus those
	-- inside an obstacle or the camp. A Forger never walks past them toward the torn edge.
	Grid = { StepStuds = 20, MarginStuds = 30 },
	-- Every part the page is built of, the gate and the markers included.
	PartBudget = 1500,
}
```

3b. In the same file, in the comment above `BattlegroundConfig.Pits`, replace

```lua
--   * Each is more than GameConfig.Vfx.BroadcastRadiusStuds (250) from the page and from the next pit: nothing
--     drawn in one is sent to anybody in another.
```

with

```lua
--   * Each is more than GameConfig.Vfx.BroadcastRadiusStuds (250) from the page and from the next pit, and clear
--     of the page's kill plane: nothing drawn in one is sent to anybody in another.
```

and in `BattlegroundConfig.Pits` replace `FirstX = 420,` with `FirstX = 650,` and add `WallThickness = 2,` after `WallHeight = 20,`. Then replace

```lua
-- its top face and BoundsHeightStuds above it. Anyone the server moved elsewhere fails it and is let go.
BattlegroundConfig.BoundsHeightStuds = 60
```

with

```lua
-- its top face and BoundsHeightStuds above it -- a jump off the highest landing included. Anyone the server moved
-- elsewhere fails it and is let go.
BattlegroundConfig.BoundsHeightStuds = 80
```

3c. Replace the whole of `src/server/Pure/BattlegroundLayout.luau` with:

```lua
--!strict
-- The Battleground's geometry (D-131, D-282), derived from BattlegroundConfig.Map: every part the map builder makes,
-- the points players land on and Forgers appear at, the ground prints a Forger walks around, and the waypoint graph
-- it finds its way on. Pure module: no require, no Roblox global. The shapes it takes are re-declared here, and
-- every number arrives through the caller, so tests/BattlegroundLayout.spec.luau holds the page to its claims --
-- every part on it, no narrow corridor, every path clear -- without an engine.
--
-- Local frame: x is east, z is south, and y = 0 is the floor's top face. A part turned by Yaw degrees is turned
-- about +y as the engine turns it (CFrame.Angles(0, rad(Yaw), 0)): its own +x points along (cos, -sin) and its own
-- +z along (sin, cos). Everything a Forger decides happens on the ground plane (x, z); heights only matter to the
-- parts.

export type Point = { X: number, Z: number }
export type Rect = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
export type Shape = "Block" | "Wedge" | "Cylinder"
export type Cover = { Name: string, X: number, Z: number, SizeX: number, SizeZ: number }
export type Piece = {
	Name: string,
	Shape: Shape,
	X: number,
	Z: number,
	Base: number,
	Size: { number },
	Yaw: number?,
}
export type Mark = {
	Name: string,
	Shape: Shape,
	X: number,
	Z: number,
	Base: number,
	SizeX: number,
	SizeZ: number,
	Yaw: number?,
}

-- The fields of BattlegroundConfig.Map this module reads.
export type MapDef = {
	Size: number,
	FloorThickness: number,
	KillZoneDepth: number,
	KillZoneSpread: number,
	KillZoneThickness: number,
	Deckle: { BandStuds: number, SlotStuds: number, Tears: { number } },
	RuleSpacingStuds: number,
	RuleWidthStuds: number,
	MarginX: number,
	Camp: Rect,
	ReturnGate: Point,
	Arrivals: { Point },
	Dais: { Size: number, Height: number },
	CoverHeight: number,
	Covers: { Cover },
	Pieces: { Piece },
	Plume: { X: number, Z: number, Yaw: number, Length: number, TipLength: number, Width: number, Height: number },
	Crater: {
		X: number,
		Z: number,
		OuterRadius: number,
		RimStuds: number,
		Height: number,
		Segments: number,
		BreachSegments: number,
	},
	Bed: { MinX: number, MaxX: number, MinZ: number, MaxZ: number, Lines: number },
	Marks: { Mark },
	BotSpawns: { Point },
	Grid: { StepStuds: number, MarginStuds: number },
}

-- What the page is dressed with, from outside BattlegroundConfig.Map: the names its readers find the floor and the
-- kill plane by (BattlegroundConfig.Anchors), the ladder's rungs and the flat slabs' thickness (WorldConfig), and
-- the camp's wash (WorldConfig.Battleground).
export type Dressing = {
	FloorName: string,
	KillZoneName: string,
	FlatThickness: number,
	RuleTop: number,
	CampTop: number,
	CampTransparency: number,
}

-- One part: its centre, size and turn in the local frame. Role is a key of WorldConfig.Battleground, the colour the
-- builder paints it. A solid part collides and blocks sight; the rest is drawn on the page.
export type Box = {
	Name: string,
	Role: string,
	Shape: Shape,
	X: number,
	Y: number,
	Z: number,
	SizeX: number,
	SizeY: number,
	SizeZ: number,
	Yaw: number,
	Solid: boolean,
	Transparency: number,
}

-- A part's print on the ground, or one grown by the path radius: its centre, its half extents along its own axes,
-- and the cosine and sine of its turn.
export type Print = { X: number, Z: number, HalfX: number, HalfZ: number, Cos: number, Sin: number }

export type Layout = {
	Boxes: { Box },
	Arrivals: { Point },
	BotSpawns: { Point },
	ReturnGate: Point,
	Camp: Rect,
	-- The page's square, torn edge included.
	Bounds: Rect,
	-- The square the waypoints cover: a Forger's goal is never past it.
	Roam: Rect,
	-- Every solid part that stands in a Forger's way (not the floor, not the dais), as its print.
	Obstacles: { Print },
	-- The obstacles and the camp, each grown by PathRadius: where no waypoint lies and no straight walk crosses.
	Blocked: { Print },
	Nodes: { Point },
	-- Edges[i]: the nodes a Forger can walk to straight from node i.
	Edges: { { number } },
	PathRadius: number,
}

local BattlegroundLayout = {}

local SQRT2 = math.sqrt(2)
-- Below this a segment has no extent along an axis, and only its position on that axis decides a hit.
local EPSILON = 1e-9
-- The solid parts a body walks on rather than around.
local GROUND = { Floor = true, Dais = true }

function BattlegroundLayout.inRect(rect: Rect, x: number, z: number): boolean
	return x >= rect.MinX and x <= rect.MaxX and z >= rect.MinZ and z <= rect.MaxZ
end

function BattlegroundLayout.inflate(rect: Rect, by: number): Rect
	return { MinX = rect.MinX - by, MaxX = rect.MaxX + by, MinZ = rect.MinZ - by, MaxZ = rect.MaxZ + by }
end

----------------------------------------------------------------
-- Prints
----------------------------------------------------------------

function BattlegroundLayout.printOf(box: Box): Print
	local yaw = math.rad(box.Yaw)
	return {
		X = box.X,
		Z = box.Z,
		HalfX = box.SizeX / 2,
		HalfZ = box.SizeZ / 2,
		Cos = math.cos(yaw),
		Sin = math.sin(yaw),
	}
end

function BattlegroundLayout.grow(print: Print, by: number): Print
	return {
		X = print.X,
		Z = print.Z,
		HalfX = print.HalfX + by,
		HalfZ = print.HalfZ + by,
		Cos = print.Cos,
		Sin = print.Sin,
	}
end

local function rectPrint(rect: Rect): Print
	return {
		X = (rect.MinX + rect.MaxX) / 2,
		Z = (rect.MinZ + rect.MaxZ) / 2,
		HalfX = (rect.MaxX - rect.MinX) / 2,
		HalfZ = (rect.MaxZ - rect.MinZ) / 2,
		Cos = 1,
		Sin = 0,
	}
end

-- A ground point in the print's own axes.
local function toPrint(print: Print, x: number, z: number): (number, number)
	local dx, dz = x - print.X, z - print.Z
	return dx * print.Cos - dz * print.Sin, dx * print.Sin + dz * print.Cos
end

function BattlegroundLayout.inPrint(print: Print, x: number, z: number): boolean
	local lx, lz = toPrint(print, x, z)
	return math.abs(lx) <= print.HalfX and math.abs(lz) <= print.HalfZ
end

-- The print's four corners on the ground.
function BattlegroundLayout.corners(print: Print): { Point }
	local out: { Point } = {}
	for _, sign in ipairs({ { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } }) do
		local lx, lz = sign[1] * print.HalfX, sign[2] * print.HalfZ
		table.insert(
			out,
			{ X = print.X + lx * print.Cos + lz * print.Sin, Z = print.Z - lx * print.Sin + lz * print.Cos }
		)
	end
	return out
end

----------------------------------------------------------------
-- Boxes
----------------------------------------------------------------

-- A solid part standing with its underside `base` studs above the floor.
local function standing(
	name: string,
	role: string,
	shape: Shape,
	x: number,
	z: number,
	base: number,
	size: { number },
	yaw: number
): Box
	return {
		Name = name,
		Role = role,
		Shape = shape,
		X = x,
		Y = base + size[2] / 2,
		Z = z,
		SizeX = size[1],
		SizeY = size[2],
		SizeZ = size[3],
		Yaw = yaw,
		Solid = true,
		Transparency = 0,
	}
end

-- A slab drawn flat, sunk into whatever it lies on, its top face at `top`.
local function drawn(
	name: string,
	role: string,
	shape: Shape,
	x: number,
	z: number,
	sizeX: number,
	sizeZ: number,
	top: number,
	yaw: number,
	dressing: Dressing
): Box
	return {
		Name = name,
		Role = role,
		Shape = shape,
		X = x,
		Y = top - dressing.FlatThickness / 2,
		Z = z,
		SizeX = sizeX,
		SizeY = dressing.FlatThickness,
		SizeZ = sizeZ,
		Yaw = yaw,
		Solid = false,
		Transparency = 0,
	}
end

local function flat(name: string, role: string, rect: Rect, top: number, dressing: Dressing): Box
	return drawn(
		name,
		role,
		"Block",
		(rect.MinX + rect.MaxX) / 2,
		(rect.MinZ + rect.MaxZ) / 2,
		rect.MaxX - rect.MinX,
		rect.MaxZ - rect.MinZ,
		top,
		0,
		dressing
	)
end

-- A piece of the floor, its top face at y = 0.
local function slab(name: string, x: number, z: number, sizeX: number, sizeZ: number, map: MapDef): Box
	return standing(name, "Floor", "Block", x, z, -map.FloorThickness, { sizeX, map.FloorThickness, sizeZ }, 0)
end

-- The floor inside the band, and the band cut in tabs, each torn in from the edge by the next of Tears: north and
-- south run the page's full width, west and east fit between them, so no two tabs overlap.
local function addFloor(boxes: { Box }, map: MapDef, dressing: Dressing)
	local deckle = map.Deckle
	local half, band, slot = map.Size / 2, deckle.BandStuds, deckle.SlotStuds
	table.insert(boxes, slab(dressing.FloorName, 0, 0, map.Size - 2 * band, map.Size - 2 * band, map))
	local count = 0
	local function tab(sideways: boolean, along: number, sign: number)
		local tear = deckle.Tears[count % #deckle.Tears + 1]
		count += 1
		local across = sign * (half - (band + tear) / 2)
		local depth = band - tear
		if sideways then
			table.insert(boxes, slab("Deckle" .. count, across, along, depth, slot, map))
		else
			table.insert(boxes, slab("Deckle" .. count, along, across, slot, depth, map))
		end
	end
	for along = -half + slot / 2, half, slot do
		tab(false, along, -1)
		tab(false, along, 1)
	end
	for along = -half + band + slot / 2, half - band, slot do
		tab(true, along, -1)
		tab(true, along, 1)
	end
end

-- The ruling (a line along x every RuleSpacingStuds, the margin along z), the camp's wash and the ink line at its
-- edge, the ruled bed and its lines: all flat on the floor.
local function addDrawing(boxes: { Box }, map: MapDef, dressing: Dressing)
	local inner = map.Size / 2 - map.Deckle.BandStuds
	local width = map.RuleWidthStuds
	local count = 0
	for z = -inner + map.RuleSpacingStuds, inner - map.RuleSpacingStuds / 2, map.RuleSpacingStuds do
		count += 1
		local line = { MinX = -inner, MaxX = inner, MinZ = z - width / 2, MaxZ = z + width / 2 }
		table.insert(boxes, flat("Rule" .. count, "Rule", line, dressing.RuleTop, dressing))
	end
	local margin = { MinX = map.MarginX - width / 2, MaxX = map.MarginX + width / 2, MinZ = -inner, MaxZ = inner }
	table.insert(boxes, flat("Margin", "Rule", margin, dressing.RuleTop, dressing))
	local camp = map.Camp
	local wash = flat("Camp", "Camp", camp, dressing.CampTop, dressing)
	wash.Transparency = dressing.CampTransparency
	table.insert(boxes, wash)
	local edge = { MinX = camp.MaxX - width / 2, MaxX = camp.MaxX + width / 2, MinZ = camp.MinZ, MaxZ = camp.MaxZ }
	table.insert(boxes, flat("CampLine", "CampLine", edge, dressing.RuleTop, dressing))
	local bed = map.Bed
	table.insert(
		boxes,
		flat(
			"Bed",
			"Bed",
			{ MinX = bed.MinX, MaxX = bed.MaxX, MinZ = bed.MinZ, MaxZ = bed.MaxZ },
			dressing.CampTop,
			dressing
		)
	)
	local gap = (bed.MaxX - bed.MinX) / (bed.Lines + 1)
	for line = 1, bed.Lines do
		local x = bed.MinX + gap * line
		local rect = { MinX = x - width / 2, MaxX = x + width / 2, MinZ = bed.MinZ, MaxZ = bed.MaxZ }
		table.insert(boxes, flat("BedLine" .. line, "Rule", rect, dressing.RuleTop, dressing))
	end
	for _, mark in ipairs(map.Marks) do
		local top = mark.Base + dressing.RuleTop
		local role = if mark.Base == 0 then "Rule" else "Trim"
		table.insert(
			boxes,
			drawn(mark.Name, role, mark.Shape, mark.X, mark.Z, mark.SizeX, mark.SizeZ, top, mark.Yaw or 0, dressing)
		)
	end
end

-- The central place: the dais, its ink edge drawn on its top, and the low walls standing on it.
local function addPlace(boxes: { Box }, map: MapDef, dressing: Dressing)
	local dais = map.Dais
	local half, width = dais.Size / 2, map.RuleWidthStuds
	table.insert(boxes, standing("Dais", "Dais", "Block", 0, 0, 0, { dais.Size, dais.Height, dais.Size }, 0))
	local top = dais.Height + dressing.RuleTop
	for _, edge in ipairs({
		{ Name = "DaisEdgeNorth", Rect = { MinX = -half, MaxX = half, MinZ = -half, MaxZ = -half + width } },
		{ Name = "DaisEdgeSouth", Rect = { MinX = -half, MaxX = half, MinZ = half - width, MaxZ = half } },
		{ Name = "DaisEdgeWest", Rect = { MinX = -half, MaxX = -half + width, MinZ = -half, MaxZ = half } },
		{ Name = "DaisEdgeEast", Rect = { MinX = half - width, MaxX = half, MinZ = -half, MaxZ = half } },
	}) do
		table.insert(boxes, flat(edge.Name, "Trim", edge.Rect, top, dressing))
	end
	for _, cover in ipairs(map.Covers) do
		local size = { cover.SizeX, map.CoverHeight, cover.SizeZ }
		table.insert(boxes, standing(cover.Name, "Cover", "Block", cover.X, cover.Z, dais.Height, size, 0))
	end
end

-- The landmarks: the listed pieces, the quill (a rising stem and its bevelled tip, end to end along its yaw) and the
-- crater's rim (a ring of blocks, each turned along the ring, minus the four breaches).
local function addLandmarks(boxes: { Box }, map: MapDef)
	for _, piece in ipairs(map.Pieces) do
		table.insert(
			boxes,
			standing(piece.Name, "Landmark", piece.Shape, piece.X, piece.Z, piece.Base, piece.Size, piece.Yaw or 0)
		)
	end
	local plume = map.Plume
	local yaw = math.rad(plume.Yaw)
	local dx, dz = math.sin(yaw), math.cos(yaw)
	local stem = plume.Length - plume.TipLength
	local stemAt = -plume.Length / 2 + stem / 2
	local tipAt = plume.Length / 2 - plume.TipLength / 2
	local stemSize = { plume.Width, plume.Height, stem }
	local tipSize = { plume.Width, plume.Height, plume.TipLength }
	table.insert(
		boxes,
		standing("PlumeStem", "Landmark", "Wedge", plume.X + dx * stemAt, plume.Z + dz * stemAt, 0, stemSize, plume.Yaw)
	)
	table.insert(
		boxes,
		standing(
			"PlumeTip",
			"Landmark",
			"Wedge",
			plume.X + dx * tipAt,
			plume.Z + dz * tipAt,
			0,
			tipSize,
			plume.Yaw + 180
		)
	)
	local crater = map.Crater
	local step = 360 / crater.Segments
	local quarter = crater.Segments / 4
	local middle = crater.OuterRadius - crater.RimStuds / 2
	local length = 2 * crater.OuterRadius * math.sin(math.rad(step / 2))
	for index = 0, crater.Segments - 1 do
		local fromAxis = index % quarter
		local breach = fromAxis < crater.BreachSegments / 2 or fromAxis >= quarter - crater.BreachSegments / 2
		if not breach then
			local angle = (index + 0.5) * step
			local x = crater.X + math.cos(math.rad(angle)) * middle
			local z = crater.Z + math.sin(math.rad(angle)) * middle
			local size = { crater.RimStuds, crater.Height, length }
			table.insert(boxes, standing("CraterRim" .. index, "Landmark", "Block", x, z, 0, size, -angle))
		end
	end
end

local function killZone(map: MapDef, dressing: Dressing): Box
	local span = map.Size * map.KillZoneSpread
	return {
		Name = dressing.KillZoneName,
		Role = "KillZone",
		Shape = "Block",
		X = 0,
		Y = map.KillZoneDepth,
		Z = 0,
		SizeX = span,
		SizeY = map.KillZoneThickness,
		SizeZ = span,
		Yaw = 0,
		Solid = false,
		Transparency = 1,
	}
end

----------------------------------------------------------------
-- Straight lines
----------------------------------------------------------------

-- Narrows [enter, leave], the share of a segment that lies inside one axis's open slab (low, high). A segment that
-- misses the slab comes back with enter >= leave.
local function clip(
	from: number,
	delta: number,
	low: number,
	high: number,
	enter: number,
	leave: number
): (number, number)
	if math.abs(delta) < EPSILON then
		if from <= low or from >= high then
			return 1, 0
		end
		return enter, leave
	end
	local t1, t2 = (low - from) / delta, (high - from) / delta
	return math.max(enter, math.min(t1, t2)), math.min(leave, math.max(t1, t2))
end

-- Whether the segment a -> b passes through the print's interior (the slab test, in the print's own axes). One that
-- only touches its edge or a corner does not: the prints are already grown by the path radius, and a goal pushed
-- out of the camp lands exactly on the grown camp's edge (clampGoal), where a Forger must still be able to walk.
-- Called for every waypoint and every print, so it allocates nothing.
local function segmentMeets(print: Print, ax: number, az: number, bx: number, bz: number): boolean
	local alx, alz = toPrint(print, ax, az)
	local blx, blz = toPrint(print, bx, bz)
	local enter, leave = clip(alx, blx - alx, -print.HalfX, print.HalfX, 0, 1)
	if enter >= leave then
		return false
	end
	enter, leave = clip(alz, blz - alz, -print.HalfZ, print.HalfZ, enter, leave)
	return enter < leave
end

-- Whether a Forger can walk straight from a to b: the segment crosses no obstacle and not the camp, both grown by
-- the Forger's path radius.
function BattlegroundLayout.segmentClear(layout: Layout, ax: number, az: number, bx: number, bz: number): boolean
	for _, print in ipairs(layout.Blocked) do
		if segmentMeets(print, ax, az, bx, bz) then
			return false
		end
	end
	return true
end

----------------------------------------------------------------
-- Waypoints
----------------------------------------------------------------

local function blocked(prints: { Print }, x: number, z: number): boolean
	for _, print in ipairs(prints) do
		if BattlegroundLayout.inPrint(print, x, z) then
			return true
		end
	end
	return false
end

-- A node every StepStuds inside Size / 2 - MarginStuds, row by row, minus those in a blocked print; each joined to
-- its eight neighbours when the straight walk between them is clear.
local function addGraph(layout: Layout, map: MapDef)
	local step = map.Grid.StepStuds
	local limit = map.Size / 2 - map.Grid.MarginStuds
	local count = math.floor(2 * limit / step) + 1
	local at: { [number]: { [number]: number } } = {}
	for row = 1, count do
		at[row] = {}
		for column = 1, count do
			local x, z = -limit + (column - 1) * step, -limit + (row - 1) * step
			if not blocked(layout.Blocked, x, z) then
				table.insert(layout.Nodes, { X = x, Z = z })
				at[row][column] = #layout.Nodes
			end
		end
	end
	for row = 1, count do
		for column = 1, count do
			local index = at[row][column]
			if index ~= nil then
				local node = layout.Nodes[index]
				local edges: { number } = {}
				for dRow = -1, 1 do
					for dColumn = -1, 1 do
						local neighbour = if at[row + dRow] ~= nil then at[row + dRow][column + dColumn] else nil
						if neighbour ~= nil and neighbour ~= index then
							local other = layout.Nodes[neighbour]
							if BattlegroundLayout.segmentClear(layout, node.X, node.Z, other.X, other.Z) then
								table.insert(edges, neighbour)
							end
						end
					end
				end
				layout.Edges[index] = edges
			end
		end
	end
end

function BattlegroundLayout.build(map: MapDef, dressing: Dressing, pathRadius: number): Layout
	local boxes: { Box } = {}
	addFloor(boxes, map, dressing)
	addDrawing(boxes, map, dressing)
	addPlace(boxes, map, dressing)
	addLandmarks(boxes, map)
	table.insert(boxes, killZone(map, dressing))

	local half = map.Size / 2
	local roam = half - map.Grid.MarginStuds
	local layout: Layout = {
		Boxes = boxes,
		Arrivals = map.Arrivals,
		BotSpawns = map.BotSpawns,
		ReturnGate = map.ReturnGate,
		Camp = map.Camp,
		Bounds = { MinX = -half, MaxX = half, MinZ = -half, MaxZ = half },
		Roam = { MinX = -roam, MaxX = roam, MinZ = -roam, MaxZ = roam },
		Obstacles = {},
		Blocked = { rectPrint(BattlegroundLayout.inflate(map.Camp, pathRadius)) },
		Nodes = {},
		Edges = {},
		PathRadius = pathRadius,
	}
	for _, box in ipairs(boxes) do
		if box.Solid and not GROUND[box.Role] then
			local print = BattlegroundLayout.printOf(box)
			table.insert(layout.Obstacles, print)
			table.insert(layout.Blocked, BattlegroundLayout.grow(print, pathRadius))
		end
	end
	addGraph(layout, map)
	return layout
end

-- The node a Forger at (x, z) should head for first: the nearest one it can walk to straight, or the nearest of all
-- when none can be reached straight. Ties go to the lower index. nil only for a graph with no node.
function BattlegroundLayout.nearestNode(layout: Layout, x: number, z: number): number?
	local best: number?, bestDistance = nil, math.huge
	local fallback: number?, fallbackDistance = nil, math.huge
	for index, node in ipairs(layout.Nodes) do
		local distance = (node.X - x) ^ 2 + (node.Z - z) ^ 2
		if distance < fallbackDistance then
			fallback, fallbackDistance = index, distance
		end
		if distance < bestDistance and BattlegroundLayout.segmentClear(layout, x, z, node.X, node.Z) then
			best, bestDistance = index, distance
		end
	end
	return best or fallback
end

-- The octile distance: exact on an eight-way grid with nothing in the way, never more than the real path.
local function octile(a: Point, b: Point): number
	local dx, dz = math.abs(a.X - b.X), math.abs(a.Z - b.Z)
	return math.max(dx, dz) + (SQRT2 - 1) * math.min(dx, dz)
end

-- The open node with the lowest estimate; ties to the lower index, so the same graph always gives the same path.
local function cheapest(open: { [number]: boolean }, estimate: { [number]: number }): number
	local best, bestScore = math.huge, math.huge
	for index in pairs(open) do
		local score = estimate[index]
		if score < bestScore or (score == bestScore and index < best) then
			best, bestScore = index, score
		end
	end
	return best
end

-- The shortest walk from node `from` to node `to` over the graph (A*), both ends included; nil when `to` cannot be
-- reached.
function BattlegroundLayout.path(layout: Layout, from: number, to: number): { number }?
	local nodes = layout.Nodes
	local goal = nodes[to]
	if nodes[from] == nil or goal == nil then
		return nil
	end
	local walked: { [number]: number } = { [from] = 0 }
	local estimate: { [number]: number } = { [from] = octile(nodes[from], goal) }
	local cameFrom: { [number]: number } = {}
	local open: { [number]: boolean } = { [from] = true }
	local openCount = 1
	while openCount > 0 do
		local current = cheapest(open, estimate)
		if current == to then
			local route = { to }
			while cameFrom[route[1]] ~= nil do
				table.insert(route, 1, cameFrom[route[1]])
			end
			return route
		end
		open[current] = nil
		openCount -= 1
		local here = nodes[current]
		for _, neighbour in ipairs(layout.Edges[current]) do
			local there = nodes[neighbour]
			local cost = walked[current] + math.sqrt((there.X - here.X) ^ 2 + (there.Z - here.Z) ^ 2)
			if walked[neighbour] == nil or cost < walked[neighbour] then
				walked[neighbour] = cost
				estimate[neighbour] = cost + octile(there, goal)
				cameFrom[neighbour] = current
				if not open[neighbour] then
					open[neighbour] = true
					openCount += 1
				end
			end
		end
	end
	return nil
end

-- Where a Forger chasing (x, z) walks to: the point brought inside the roam, then, inside the camp grown by the
-- path radius, pushed out across its nearest edge that stays in the roam. A Forger never walks into the camp nor
-- toward the torn edge, whatever it chases.
function BattlegroundLayout.clampGoal(layout: Layout, x: number, z: number): (number, number)
	local roam = layout.Roam
	x = math.clamp(x, roam.MinX, roam.MaxX)
	z = math.clamp(z, roam.MinZ, roam.MaxZ)
	local camp = BattlegroundLayout.inflate(layout.Camp, layout.PathRadius)
	if not BattlegroundLayout.inRect(camp, x, z) then
		return x, z
	end
	local bestX, bestZ, bestShift = x, z, math.huge
	for _, exit in ipairs({ { camp.MaxX, z }, { camp.MinX, z }, { x, camp.MinZ }, { x, camp.MaxZ } }) do
		local ex, ez = exit[1], exit[2]
		local shift = math.abs(ex - x) + math.abs(ez - z)
		if shift < bestShift and BattlegroundLayout.inRect(roam, ex, ez) then
			bestX, bestZ, bestShift = ex, ez, shift
		end
	end
	return bestX, bestZ
end

return BattlegroundLayout
```

3d. In `src/shared/Config/WorldConfig.luau`, replace the comment and table of `WorldConfig.Battleground` (from `-- The Battleground (D-131): a page walled in bone` to its closing `}`) with:

```lua
-- The Battleground (D-131, D-282): a page with a torn edge, ruled in ink like the hub, a chalk dais at its centre
-- with ink walls on it, landmarks and a ruled bed in bone. The camp, where players arrive, is washed grey behind an
-- ink line. Every Role of BattlegroundLayout's boxes is a key of this table.
WorldConfig.Battleground = {
	Floor = "Page",
	Rule = "Ink",
	Trim = "Ink",
	Dais = "Chalk",
	Cover = "Ink",
	Landmark = "Bone",
	Bed = "Bone",
	Camp = "Wash",
	CampLine = "Ink",
	KillZone = "Page",
	Marker = "Page",
	CampTransparency = 0.4,
}
```

3e. In `src/server/Services/BattlegroundService/Map.luau`:

- Header: replace `-- Map: builds Workspace.Battleground (D-131) from BattlegroundLayout,` … `-- sight rays' filter. About sixty static parts, never released.` with

```lua
-- Map: builds Workspace.Battleground (D-131, D-282) from BattlegroundLayout, once, at Start, and hands the rest of
-- the service what it measures against -- the layout, the landing and spawn markers, the kill plane and the
-- sight rays' filter. A few hundred static parts (BattlegroundConfig.Map.PartBudget), never released.
```

  and replace the paragraph `-- The solids -- the floor, the walls, the pillars, the stele and the cover -- also carry` … `-- its noclip ray against. The kill plane, the rules and the camp touch nothing and are left out.` with

```lua
-- The solids -- the floor and its torn edge, the dais, the cover and the landmarks -- also carry
-- MovementGuardConfig.BarrierTag: the geometry no body may pass through, which is all the movement audit casts
-- its noclip ray against. The kill plane, the ink drawn on the page and the camp touch nothing and are left out.
-- A box is a block, a wedge or a cylinder, turned by its Yaw about the vertical; a cylinder's axis is the engine's
-- x, so it is laid on its side to stand on its flat face.
```

- After `local COLLISION_TAG = WorldConfig.Glyphs.CollisionTag` add:

```lua
-- Lays a cylinder's axis (the engine's x) along the vertical.
local CYLINDER_UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)
```

- In `DRESSING`, delete the two lines `WallRuleStuds = WorldConfig.Arena.WallRuleStuds,` and `WallRuleProudStuds = WorldConfig.Arena.WallRuleProudStuds,`.
- Replace the first two lines of `newPart` (`local function newPart(name: string, size: Vector3, cframe: CFrame, role: string): Part` and `local part = Instance.new("Part")`) with:

```lua
local function newPart(name: string, shape: BattlegroundLayout.Shape, size: Vector3, cframe: CFrame, role: string): BasePart
	local part: BasePart
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		if shape == "Cylinder" then
			block.Shape = Enum.PartType.Cylinder
		end
		part = block
	end
```

- Replace the comment and the head of `buildBox` (down to and including the `newPart(...)` call) with:

```lua
-- One box of the layout. A solid collides and can be hit by a query; the rest -- the ruling, the camp's wash, the
-- bed, the ink marks -- is drawn on the page and is nothing to the physics.
local function buildBox(box: BattlegroundLayout.Box, parent: Model): BasePart
	local frame = CFrame.new(Context.toWorld(box.X, box.Y, box.Z)) * CFrame.Angles(0, math.rad(box.Yaw), 0)
	local size = Vector3.new(box.SizeX, box.SizeY, box.SizeZ)
	if box.Shape == "Cylinder" then
		frame *= CYLINDER_UPRIGHT
		size = Vector3.new(box.SizeY, box.SizeX, box.SizeZ)
	end
	local part = newPart(box.Name, box.Shape, size, frame, box.Role)
```

- Replace the head of `buildMarker` (its signature, `local position = ...` and the two-line `local marker = newPart(...)`) with:

```lua
local function buildMarker(name: string, point: BattlegroundLayout.Point, face: Vector3, parent: Model): BasePart
	local position = Context.toWorld(point.X, BattlegroundConfig.StandingRootStuds, point.Z)
	local frame = CFrame.lookAt(position, Vector3.new(face.X, position.Y, face.Z))
	local marker = newPart(name, "Block", MARKER_STUDS, frame, MARKER_ROLE)
```

- In `Map.build`, replace the arrivals loop with:

```lua
	for index, point in ipairs(layout.Arrivals) do
		-- Facing the page's centre, the way a player walks out of the camp or in from the edge.
		table.insert(arrivals, buildMarker(ANCHORS.Arrival .. index, point, Context.Origin, model))
	end
```

  and replace the comment `-- Facing east, the way its players come from the page; its back posts end on the west wall.` with `-- Facing east, the way its players come from the page; its back posts end on the camp's west edge.`

3f. In `src/server/Services/BattlegroundService/Motion.luau`, replace the comment above `Motion.walkTo` and its first line:

```lua
-- Walks toward (x, z) of the page's frame, never into the camp nor past the roam (clampGoal). The order is re-issued
-- only when the goal moved RepathStuds, after RepathSeconds, or on reaching the waypoint it walks to -- a path is
-- searched at most a couple of times a second per Forger.
function Motion.walkTo(bot: Bot, x: number, z: number, now: number)
	local gx, gz = BattlegroundLayout.clampGoal(handle.Layout, x, z)
```

3g. In `src/server/Services/BattlegroundService/Pits.luau` (`buildPit`), replace `local size, height, thickness = PITS.Size, PITS.WallHeight, MAP.WallThickness` with `local size, height, thickness = PITS.Size, PITS.WallHeight, PITS.WallThickness`.

3h. Follow the removed walls in three specs:
- `tests/SparPits.spec.luau`: `local half = PITS.Size / 2 + MAP.WallThickness` becomes `local half = PITS.Size / 2 + PITS.WallThickness`, and `local pageEast = MAP.Size / 2 + MAP.WallThickness` becomes `local pageEast = MAP.Size / 2`.
- `tests/MovementGates.spec.luau`: in both `dressing` tables delete `WallRuleStuds = WorldConfig.Arena.WallRuleStuds,` and `WallRuleProudStuds = WorldConfig.Arena.WallRuleProudStuds,`; replace `local barriers = { Floor = true, Wall = true, Pillar = true, Stele = true, Cover = true }` with `local barriers = { Floor = true, Dais = true, Cover = true, Landmark = true }`.
- `tests/Config.spec.luau` (`BattlegroundConfig: membership`): delete the two lines `-- Up to the top of the walls: a member thrown against one is still on the page.` and `expect(BattlegroundConfig.BoundsHeightStuds).toBeGreaterThanOrEqual(BattlegroundConfig.Map.WallHeight)` (the layout spec now holds the height against the highest landing).

- [ ] **Step 4: Format and run the gates**

Run: `stylua src tests && lune run tests/run 2>&1 | grep -E "✖|passed|failed to load" -A1`
Expected: `0 failed` (2 532 or more passed, 183 spec files).
Run: `scripts/check.sh`
Expected: `✔ all quality gates green`. A luau-lsp `Key 'clampOutOfCamp' not found` means 3f was skipped; a Selene `shadowing` warning means a local named `gap` crept into the spec beside the helper.

- [ ] **Step 5: Commit**

```bash
git add src/shared/Config/BattlegroundConfig.luau src/server/Pure/BattlegroundLayout.luau src/shared/Config/WorldConfig.luau src/server/Services/BattlegroundService/Map.luau src/server/Services/BattlegroundService/Motion.luau src/server/Services/BattlegroundService/Pits.luau tests/BattlegroundLayout.spec.luau tests/SparPits.spec.luau tests/MovementGates.spec.luau tests/Config.spec.luau
git commit -m "feat(battleground): the 700-stud page, its landmarks and a 20-stud Forger grid" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Every member against every other, behind a 3 s arrival bubble

**Files:**
- Modify: `src/shared/Config/ZoneConfig.luau`, `src/server/Services/CombatService.luau`, `src/shared/Config/BattlegroundConfig.luau`
- Modify: `src/server/Services/BattlegroundService/Context.luau`, `Roster.luau` (`Roster.admit`, header), `init.luau` (`Start`, header)
- Test: `tests/DamageZones.spec.luau`, `tests/Battleground.spec.luau`, `tests/SparPits.spec.luau` (stub)

**Interfaces:**
- Consumes: Task 1's page (members stand on it); `CombatService.claimZone(zone: ZoneId, claim: ZoneClaim)`, `isSpawnProtected` (local), `DamageZones.judge`.
- Produces:
  - `ZoneConfig.ZoneId` gains `"Battleground"`; `ZoneConfig.Order = { "Match", "Boss", "Flyleaf", "Battleground", "Hub" }`; `ZoneConfig.Rules.Battleground = { BetweenPlayers = "Owner", OnBodies = true, CombatPaysKills = false }`.
  - `CombatService.protect(player: Player, seconds: number)` and `CombatService.isProtected(player: Player): boolean`.
  - `BattlegroundConfig.ArrivalProtectionSeconds = 3`.
  - `Context.ZoneClaim` and `Context.CombatApi` fields `claimZone: (zone: "Battleground", claim: ZoneClaim) -> ()`, `protect: (player: Player, seconds: number) -> ()`, `isProtected: (player: Player) -> boolean`.

- [ ] **Step 1: Write the failing tests**

In `tests/DamageZones.spec.luau`, rule test `it("is the story's: ...")`: rename it to `it("is the story's: the hub none, a match its participants, the Erasure never, the pages their members", function()`, add `expect(RULES.Battleground.BetweenPlayers).toBe("Owner")` after the Flyleaf `BetweenPlayers` line, add

```lua
		-- The Battleground's members fight the Forgers as well as each other.
		expect(RULES.Battleground.OnBodies).toBe(true)
```

after `expect(RULES.Flyleaf.OnBodies).toBe(false)`, and `expect(DamageZones.combatPays(RULES, "Battleground")).toBe(false)` after the Flyleaf `combatPays` line. Then insert these three cases in `describe("CombatService's zones", ...)`, before `it("leave a Flyleaf kill to the page, ...")`:

```lua
	it("let the Battleground's members fight each other and the Forgers, and nobody from outside (D-282)", function()
		local fx = fixture()
		local a, b, outsider = fx.join(1, 0), fx.join(2, 4), fx.join(3, 8)
		local forger = fx.proof(12)
		owner(fx, "Battleground", { a, b })
		fx.settle()
		expect(fx.combat.zoneOf(a)).toBe("Battleground")
		expect(fx.combat.ApplyDamage(a, b.Character, 20, "Melee", {}).Applied).toBe(20)
		expect(fx.combat.ApplyDamage(b, a.Character, 20, "Melee", {}).Applied).toBe(20)
		expect(fx.combat.canDamage(outsider, a.Character)).toBe(false)
		expect(fx.combat.canDamage(a, outsider.Character)).toBe(false)
		expect(fx.combat.ApplyDamage(a, forger, 20, "Melee", {}).Applied).toBe(20)
	end)

	it("hold every blow off a bubble's wearer until it runs out or they strike, and burst it on their blow", function()
		local fx = fixture()
		local a, b = fx.join(1, 0), fx.join(2, 4)
		owner(fx, "Battleground", { a, b })
		fx.settle()
		fx.combat.protect(b, 3)
		expect(fx.combat.isProtected(b)).toBe(true)
		expect(fx.combat.ApplyDamage(a, b.Character, 20, "Melee", {}).Applied).toBe(0)
		-- A Forger's blow carries no player, and is held off too.
		expect(fx.combat.ApplyDamage(nil, b.Character, 20, "Melee", {}).Applied).toBe(0)
		-- The wearer strikes: the blow lands, and the bubble is gone.
		expect(fx.combat.canDamage(b, a.Character)).toBe(true)
		expect(fx.combat.ApplyDamage(b, a.Character, 20, "Melee", {}).Applied).toBe(20)
		expect(fx.combat.isProtected(b)).toBe(false)
		expect(fx.combat.ApplyDamage(a, b.Character, 20, "Melee", {}).Applied).toBe(20)
		-- Left alone, a bubble runs out on its own.
		fx.combat.protect(a, 3)
		fx.world.engine.now += 2.9
		expect(fx.combat.canDamage(b, a.Character)).toBe(false)
		fx.world.engine.now += 0.2
		expect(fx.combat.canDamage(b, a.Character)).toBe(true)
	end)

	it("take the hub's ForceField off a body the bubble replaces, and keep the hub's protection whole", function()
		local fx = fixture()
		local a, b = fx.join(1, 0), fx.join(2, 4)
		local dummy = fx.proof(8)
		-- Fresh from the SpawnLocation, the hub's protection holds its wearer's own blow back, and does not burst.
		expect(fx.combat.ApplyDamage(a, dummy, 20, "Melee", {}).Applied).toBe(0)
		expect(fx.combat.isProtected(a)).toBe(true)
		require("./engine").instance("ForceField", b.Character)
		owner(fx, "Battleground", { a, b })
		fx.combat.protect(b, 3)
		expect(b.Character:FindFirstChildOfClass("ForceField")).toBeNil()
		expect(fx.combat.ApplyDamage(b, dummy, 20, "Melee", {}).Applied).toBe(20)
		expect(fx.combat.isProtected(b)).toBe(false)
	end)
```

In `tests/Battleground.spec.luau`, insert before `describe("a Forger's kill", function()`:

```lua
describe("the page's free-for-all (D-282)", function()
	it("claims the Battleground zone for its members, any pair of them", function()
		local start = body(module("init"), "function BattlegroundService.Start(", "init")
		expect(start).toContain(
			'deps.Combat.claimZone("Battleground", { Holds = function(player: Player): boolean return Roster.get(player) ~= nil end, Pair = function(_source: Player, _target: Player): boolean return true end, })'
		)
	end)

	it("puts the arrival bubble on every member it admits, through the gate or back from a death", function()
		local admit = body(module("Roster"), "function Roster.admit(", "Roster")
		expect(ordered(admit, "members[player] = member", "deps.Combat.protect(player, BattlegroundConfig.ArrivalProtectionSeconds)")).toBe(true)
	end)
end)
```

(Both ways in already go through `Roster.admit`: the existing gate "is placed with trust re-anchored on the landing the server chose" orders `Roster.place` before `Roster.admit` in `enter` and in `redirect`.)

- [ ] **Step 2: Run them to verify they fail**

Run: `lune run tests/run 2>&1 | grep -E "✖|passed|failed to load" -A1`
Expected: FAIL on the rule test (`attempt to index nil with 'BetweenPlayers'`), on the three new `CombatService's zones` cases (`attempt to call a nil value (field 'protect')` or the zone's rule missing), and on the two new `the page's free-for-all` gates (`to contain` / `to be true`).

- [ ] **Step 3: Implement the zone and the bubble**

3a. `src/shared/Config/ZoneConfig.luau`: replace the header paragraph from `-- Every player stands in one zone at a time,` to `-- never a zone's business.` with

```lua
-- Every player stands in one zone at a time, the first of Order whose owner claims them (CombatService.claimZone):
-- a match holds its participants, the Erasure's fight the players it engaged, the Flyleaf and the Battleground their
-- members, and the hub everybody else. A hit from one player on another lands only when both stand in the same zone
-- and that zone lets players hurt each other there -- and then its owner judges the pair (opponents of the same live
-- match, two members of the Flyleaf out of their protection, any two members of the Battleground). Damage the server
-- authors (the boss, the Forgers, the arenas' kill planes) carries no player and is never a zone's business.
```

then `export type ZoneId = "Match" | "Boss" | "Flyleaf" | "Battleground" | "Hub"`, `ZoneConfig.Order = { "Match", "Boss", "Flyleaf", "Battleground", "Hub" } :: { ZoneId }`, and after the `Flyleaf = { ... },` rule:

```lua
	-- The Battleground (D-282): every member against every other, and the Forgers against all of them; the page pays
	-- its own player kills, under its pair rule and the Forgers' daily cap.
	Battleground = { BetweenPlayers = "Owner", OnBodies = true, CombatPaysKills = false },
```

3b. `src/server/Services/CombatService.luau`:
- In the `State` type, after `SpawnProtectedUntil: number,` add

```lua
	-- The protection is a bubble (protect): it never holds its wearer's own blow back, and that blow bursts it.
	BubbleBursts: boolean,
```

- In `resetState`, after `state.SpawnProtectedUntil = now + GameConfig.Spawn.ProtectionSeconds` add `state.BubbleBursts = false`; in the new-state table, after `SpawnProtectedUntil = 0,` add `BubbleBursts = false,`.
- In `refuses`, replace `if isSpawnProtected(stateOf(source), sourceCharacter, now) or isSpawnProtected(targetState, targetModel, now) then` with

```lua
	local sourceState = stateOf(source)
	local sourceHeld = isSpawnProtected(sourceState, sourceCharacter, now)
		and not (sourceState ~= nil and sourceState.BubbleBursts)
	if sourceHeld or isSpawnProtected(targetState, targetModel, now) then
```

- In `CombatService.ApplyDamage`, right after `local targetState = stateOf(targetPlayer)` (before the per-source i-frames comment) add

```lua
	-- A bubble bursts on the first blow its wearer strikes that gets this far, whether or not it lands (protect).
	if sourceState ~= nil and sourceState.BubbleBursts then
		sourceState.BubbleBursts = false
		sourceState.SpawnProtectedUntil = 0
	end
```

- Before `-- Whether `player` is kept in a hold now, whoever opened it` (`CombatService.isChanneling`) add

```lua
-- A bubble on `player` for `seconds` from now (the Battleground's arrival, D-282): nobody hurts them while it holds,
-- and the first blow they strike themselves bursts it (ApplyDamage). It replaces the hub's spawn protection on this
-- body, the SpawnLocation's ForceField included, which no blow could burst.
function CombatService.protect(player: Player, seconds: number)
	local state = states[player]
	if state == nil then
		return
	end
	state.SpawnProtectedUntil = os.clock() + seconds
	state.BubbleBursts = true
	local character = player.Character
	if character ~= nil then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("ForceField") then
				child:Destroy()
			end
		end
	end
end

-- Whether nobody may hurt `player` now: the hub's spawn protection or a bubble still holds. The Battleground pays
-- nothing for a victim under either (D-282).
function CombatService.isProtected(player: Player): boolean
	local state = states[player]
	return state ~= nil and isSpawnProtected(state, player.Character, os.clock())
end
```

- In the comment above `CombatService.claimZone`, replace its first four lines with

```lua
-- The owner of a zone (ZoneConfig) says who it holds and, where players may hurt each other there, which pairs may
-- (E16-S1): MatchService its participants, WorldBossService the players its fight engaged, FlyleafService and
-- BattlegroundService their members. The rules run after spawn protection, i-frames and a body on the ground. One
-- owner per zone: the hub is everybody no owner holds and is claimed by nobody, and a zone whose players may hurt
-- each other needs its Pair.
```

3c. `src/shared/Config/BattlegroundConfig.luau`, after `BattlegroundConfig.StandingRootStuds = 3.5`:

```lua
-- Arriving, and every time a member comes back to the page, nobody hurts them for this long; the first blow they
-- strike themselves ends it at once (CombatService.protect).
BattlegroundConfig.ArrivalProtectionSeconds = 3
```

3d. `src/server/Services/BattlegroundService/Context.luau`: after `export type DamageResult = ...` add

```lua
export type ZoneClaim = {
	Holds: (player: Player) -> boolean,
	Pair: ((source: Player, target: Player) -> boolean)?,
}
```

and in `CombatApi`, after the `heal` field:

```lua
	-- The page's members are the Battleground zone, where any two of them may hurt each other (ZoneConfig, D-282).
	claimZone: (zone: "Battleground", claim: ZoneClaim) -> (),
	-- A bubble that holds every blow off `player` for `seconds` and bursts on the first one they strike.
	protect: (player: Player, seconds: number) -> (),
	-- Whether nobody may hurt `player` now: their spawn protection or their bubble still holds.
	isProtected: (player: Player) -> boolean,
```

3e. `src/server/Services/BattlegroundService/Roster.luau`: in the header, replace `-- with no hook in any of those services.` with

```lua
-- with no hook in any of those services. Every admission -- through the gate or back from a death -- puts the
-- arrival bubble on the member (CombatService.protect, D-282).
```

and in `Roster.admit`, right after `members[player] = member`, add `deps.Combat.protect(player, BattlegroundConfig.ArrivalProtectionSeconds)`.

3f. `src/server/Services/BattlegroundService/init.luau`: replace the header's first three lines with

```lua
-- BattlegroundService: the Battleground (D-131, D-282), a permanent page built in code at world X = 1500 where every
-- member may hurt every other and the Forgers -- server-owned ink figures driven by BotBrain -- come at all of them.
-- The page claims the Battleground zone (CombatService.claimZone): its members, any pair of them. Whoever is admitted
-- wears a bubble for ArrivalProtectionSeconds (Roster.admit), and a member's kill of another is paid by Rewards.
```

and in `BattlegroundService.Start`, after `trove:Add(deps.Movement.BodyLost:Connect(Roster.lost))`:

```lua
	deps.Combat.claimZone("Battleground", {
		Holds = function(player: Player): boolean
			return Roster.get(player) ~= nil
		end,
		Pair = function(_source: Player, _target: Player): boolean
			return true
		end,
	})
```

3g. `tests/SparPits.spec.luau` runs the real `Roster` (`nextBodyToCamp`): in its `Combat` stub, after the `trustedPosition` function, add `protect = function() end,`.

- [ ] **Step 4: Format and run the gates**

Run: `stylua src tests && lune run tests/run 2>&1 | grep -E "✖|passed|failed to load" -A1`
Expected: `0 failed`. `DamageZones.spec`'s "the single PvP slot is gone" still passes: the server claims `Battleground` exactly once, with a literal.
Run: `scripts/check.sh`
Expected: `✔ all quality gates green`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/Config/ZoneConfig.luau src/server/Services/CombatService.luau src/shared/Config/BattlegroundConfig.luau src/server/Services/BattlegroundService/Context.luau src/server/Services/BattlegroundService/Roster.luau src/server/Services/BattlegroundService/init.luau tests/DamageZones.spec.luau tests/Battleground.spec.luau tests/SparPits.spec.luau
git commit -m "feat(battleground): every member against every other, behind a 3 s bubble" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: A member's kill pays once per pair, under the Forgers' daily cap; D-282 in the docs

**Files:**
- Modify: `src/shared/Config/BattlegroundConfig.luau`, `src/server/Services/BattlegroundService/Rewards.luau`, `Roster.luau` (`Roster.holds`), `init.luau` (`onKilled`, `tick`)
- Modify: `src/server/Config/AnalyticsConfig.luau`, `src/shared/Strings.luau`, `localization.csv` (generated)
- Test: `tests/Battleground.spec.luau`, `tests/EconomyEvents.spec.luau`
- Docs: `docs/GAME_DESIGN.md`, `docs/ECONOMY.md`, `docs/DECISIONS.md`, `docs/PROGRESS.md`

**Interfaces:**
- Consumes: Task 2's `deps.Combat.isProtected(player): boolean`; `FlyleafRules.recordKill(ledger, killerId, victimId, now, rules): boolean`, `FlyleafRules.prune(ledger, now, rules)`, `FlyleafRules.Ledger`, `FlyleafRules.FarmRules`; `DailyCap.take`; profile `Daily.ForgerDay` / `Daily.ForgerFolios`; `BotConfig.Credit.DailyFolioCap` (150); `CombatService.Killed` (fires for every kill, Forger or player).
- Produces:
  - `BattlegroundConfig.PlayerKill = { Xp = 60, Folios = 3, PairCooldownSeconds = 300 }`.
  - `Rewards.payPlayer(killer: Player, victim: Player, now: number)`, `Rewards.prune(now: number)`.
  - `Roster.holds(player: Player): boolean` (a member, or a member who died inside and whose next body the page waits for).
  - Analytics reason `"BattlegroundKill"` (`AnalyticsConfig.Transactions.BattlegroundKill = "Gameplay"`).

- [ ] **Step 1: Write the failing tests**

In `tests/Battleground.spec.luau`, replace header lines 2-3 (`-- The Battleground on the server (D-131), held to the promises no Lune test can run: every service here needs` and `-- an engine, so their sources are read. Each case is a rule a Forger or the roster must never break -- damage`) with

```lua
-- The Battleground on the server (D-131, D-282), held to the promises no Lune test can run: every service here needs
-- an engine, so their sources are read -- all but Rewards, run on a pretend server (tests/server.luau). Each case is
-- a rule a Forger or the roster must never break -- damage
```

(lines 4-6 stay), replace the requires block `local Harness = require("./harness")` / `local fs = require("@lune/fs")` with

```lua
local BattlegroundConfig = require("../src/shared/Config/BattlegroundConfig")
local BotConfig = require("../src/shared/Config/BotConfig")
local DailyStreak = require("../src/shared/Pure/DailyStreak")
local Harness = require("./harness")
local Server = require("./server")
local fs = require("@lune/fs")
```

and insert before `describe("a Forger's kill", function()`:

```lua
-- Rewards on a pretend server, the roster and the bubble stubbed: what a member's kill of another pays.
type Kills = {
	rewards: any,
	held: { [any]: boolean },
	shielded: { [any]: boolean },
	xp: { [any]: number },
	folios: { [any]: number },
	profiles: { [any]: any },
	said: { string },
	join: (userId: number) -> any,
}

local function kills(): Kills
	local fx: any = { held = {}, shielded = {}, xp = {}, folios = {}, profiles = {}, said = {} }
	local world = Server.world({
		Stubs = {
			[DIR .. "Bots"] = {},
			[DIR .. "Map"] = {},
			[DIR .. "Roster"] = {
				holds = function(player: any): boolean
					return fx.held[player] == true
				end,
			},
		},
	})
	fx.rewards = world.require(DIR .. "Rewards")
	fx.rewards.Init({
		DataService = {
			get = function(player: any): any
				local data = fx.profiles[player]
				if data == nil then
					data = { Daily = { ForgerDay = 0, ForgerFolios = 0 } }
					fx.profiles[player] = data
				end
				return data
			end,
			push = function(_player: any, _section: string) end,
		},
		Notify = {
			send = function(_player: any, key: string, _params: any, _kind: any, _sfx: any)
				table.insert(fx.said, key)
			end,
		},
		Combat = {
			isProtected = function(player: any): boolean
				return fx.shielded[player] == true
			end,
		},
		Progression = {
			addXp = function(player: any, amount: number, _reason: string): number
				fx.xp[player] = (fx.xp[player] or 0) + amount
				return amount
			end,
		},
		Currency = {
			add = function(player: any, amount: number, _reason: string): number
				fx.folios[player] = (fx.folios[player] or 0) + amount
				return amount
			end,
		},
	}, {})
	function fx.join(userId: number): any
		local player = world:join(userId, "P" .. userId)
		fx.held[player] = true
		return player
	end
	return fx :: Kills
end

describe("a member's kill of another (D-282)", function()
	local KILL = BattlegroundConfig.PlayerKill

	it("pays once, then nothing for the same victim until the pair has rested PairCooldownSeconds", function()
		local fx = kills()
		local a, b = fx.join(1), fx.join(2)
		fx.rewards.payPlayer(a, b, 100)
		expect(fx.xp[a]).toBe(KILL.Xp)
		expect(fx.folios[a]).toBe(KILL.Folios)
		expect(table.find(fx.said, "hud.playerKill") ~= nil).toBe(true)
		fx.rewards.payPlayer(a, b, 100 + KILL.PairCooldownSeconds - 1)
		expect(fx.xp[a]).toBe(KILL.Xp)
		-- The other way round is another pair.
		fx.rewards.payPlayer(b, a, 101)
		expect(fx.xp[b]).toBe(KILL.Xp)
		-- PairCooldownSeconds after the pair's last kill, paid or not, it pays again.
		fx.rewards.payPlayer(a, b, 100 + 2 * KILL.PairCooldownSeconds)
		expect(fx.xp[a]).toBe(2 * KILL.Xp)
	end)

	it("pays nothing under a bubble, nor for a killer or a victim the page does not hold, nor for oneself", function()
		local fx = kills()
		local a, b = fx.join(1), fx.join(2)
		fx.shielded[b] = true
		fx.rewards.payPlayer(a, b, 0)
		fx.shielded[b] = false
		fx.held[a] = false
		fx.rewards.payPlayer(a, b, 0)
		fx.held[a] = true
		-- A victim who walked home before the death the hub credits to the last blow.
		fx.held[b] = false
		fx.rewards.payPlayer(a, b, 0)
		fx.held[b] = true
		fx.rewards.payPlayer(a, a, 0)
		expect(fx.xp[a]).toBeNil()
		-- None of those took the pair's payment.
		fx.rewards.payPlayer(a, b, 1)
		expect(fx.xp[a]).toBe(KILL.Xp)
	end)

	it("takes its Folios out of the Forgers' daily allowance in the profile, and says once when it is spent", function()
		local fx = kills()
		local a, b, c = fx.join(1), fx.join(2), fx.join(3)
		local cap = BotConfig.Credit.DailyFolioCap
		fx.profiles[a] = { Daily = { ForgerDay = DailyStreak.dayIndex(os.time()), ForgerFolios = cap - 1 } }
		fx.rewards.payPlayer(a, b, 0)
		expect(fx.folios[a]).toBe(1)
		expect(fx.profiles[a].Daily.ForgerFolios).toBe(cap)
		fx.rewards.payPlayer(a, c, 0)
		expect(fx.folios[a]).toBe(1)
		expect(fx.xp[a]).toBe(2 * KILL.Xp)
		fx.rewards.payPlayer(b, c, 0)
		local told = 0
		for _, key in ipairs(fx.said) do
			if key == "battleground.folioCap" then
				told += 1
			end
		end
		expect(told).toBe(1)
	end)

	it("is heard on Killed for a player's body, before any Forger is looked for, and pruned every tick", function()
		local init = module("init")
		local killed = body(init, "local function onKilled(", "init")
		expect(
			ordered(
				killed,
				'log.try("Rewards.payPlayer", Rewards.payPlayer, killer, victim, os.clock())',
				"Bots.byModel(model)"
			)
		).toBe(true)
		expect(body(init, "local function tick(", "init")).toContain("Rewards.prune(now)")
	end)
end)
```

In `tests/EconomyEvents.spec.luau`, replace `local function botReasons(): { string }` with

```lua
-- What the Battleground pays under: each Forger tier's RewardKey, and a member's kill of another (D-282).
local function battlegroundReasons(): { string }
```

add `table.insert(reasons, "BattlegroundKill")` after its `for` loop (before `table.sort(reasons)`), and replace the site `{ File = "BattlegroundService/Rewards", Call = "(player, folios, key)", Flow = "Source", Reasons = botReasons() },` with

```lua
	-- A Forger's kill, and a member's kill of another, under the same daily cap (D-282).
	{ File = "BattlegroundService/Rewards", Call = "(player, folios, reason)", Flow = "Source", Reasons = battlegroundReasons() },
```

- [ ] **Step 2: Run them to verify they fail**

Run: `lune run tests/run 2>&1 | grep -E "✖|passed|failed to load" -A1`
Expected: FAIL on the four `a member's kill of another (D-282)` cases (`attempt to call a nil value (field 'payPlayer')`, and the `onKilled` gate's `to be true`) and on `every call that moves Folios (E8-S1)` (the site `(player, folios, reason)` is not in `Rewards.luau` yet, and `BattlegroundKill` has no transaction type).

- [ ] **Step 3: Implement the pay**

3a. `src/shared/Config/BattlegroundConfig.luau`, after `BattlegroundConfig.ArrivalProtectionSeconds = 3`:

```lua
-- What one member's kill of another pays its killer: XP, and Folios out of the same daily allowance as the
-- Forgers' (BotConfig.Credit.DailyFolioCap). A pair pays once, then nothing until PairCooldownSeconds have passed
-- since its last kill, paid or not (FlyleafRules.recordKill).
BattlegroundConfig.PlayerKill = { Xp = 60, Folios = 3, PairCooldownSeconds = 300 }
```

3b. `src/server/Services/BattlegroundService/Rewards.luau`:
- Replace header lines 2-5 (from `-- Rewards: what a fallen Forger pays (D-131). The killer and everyone whose damage reached` to `-- from the camp counts toward a share at all (BotBrain.creditHit).`) with

```lua
-- Rewards: what a fallen Forger pays (D-131), and what a member's kill of another pays (D-282). The killer and
-- everyone whose damage reached BotConfig.Credit.AssistShare of its health are paid -- if they are members, and not
-- from where a Forger cannot answer: the camp, a place it has given up reaching, or UnreachableSeconds off the floor.
-- Nothing dealt from the camp counts toward a share at all (BotBrain.creditHit).
```

  and after the header line `-- the cap a kill pays XP alone, and the player is told once per day and per session.` add

```lua
--
-- A member's kill of another pays its killer PlayerKill.Xp, and PlayerKill.Folios out of the same allowance. A pair
-- pays once, then nothing until PairCooldownSeconds have passed since its last kill, paid or not (the Flyleaf's
-- ledger, FlyleafRules.recordKill, one paid death per window); nothing for a victim still under their bubble, nor
-- for a killer or a victim the page does not hold.
```

- Add `local BattlegroundConfig = require(Shared.Config.BattlegroundConfig)` before the `BattlegroundLayout` require, and `local FlyleafRules = require(script.Parent.Parent.Parent.Pure.FlyleafRules)` after the `DailyStreak` require.
- After `local FOLIOS = ...` add

```lua
local KILL = BattlegroundConfig.PlayerKill
local FARM: FlyleafRules.FarmRules = { MaxPaidDeaths = 1, WindowSeconds = KILL.PairCooldownSeconds }
-- The reason a member's kill of another is credited under (analytics, the result of addXp and add).
local KILL_REASON = "BattlegroundKill"
```

- Replace `-- Player -> the day they were last told the Forgers pay no more Folios.` with `-- Player -> the day they were last told the page pays no more Folios.`, and after `local capToldOn: { [Player]: number } = {}` add

```lua
-- Every member's kill of another, by killer and victim: what the pair rule reads.
local ledger: FlyleafRules.Ledger = {}
```

- Replace the comment and signature of `takeFolios` and its `DailyCap.take` line:

```lua
-- Takes `want` of today's Folios from the profile's allowance and writes the count back. Returns what may be paid,
-- before VIP (CurrencyService applies it); nil with no profile loaded, which is no cap reached.
local function takeFolios(player: Player, want: number, today: number): number?
```

```lua
	local granted, used = DailyCap.take(daily.ForgerDay, daily.ForgerFolios, today, CREDIT.DailyFolioCap, want)
```

- Replace the start of `payOne`, from `local function payOne(` through the `end` that closes its Folio `if`/`elseif`, with

```lua
-- Pays `want` Folios under `reason` out of today's allowance, or tells the player, once a day, that it is spent.
local function payFolios(player: Player, want: number, reason: string)
	local today = DailyStreak.dayIndex(os.time())
	local folios = takeFolios(player, want, today)
	if folios ~= nil and folios >= 1 then
		deps.Currency.add(player, folios, reason)
	elseif folios ~= nil and capToldOn[player] ~= today then
		capToldOn[player] = today
		deps.Notify.send(player, "battleground.folioCap", nil, "Info")
	end
end

local function payOne(player: Player, member: Roster.Member, key: string, killer: boolean)
	local xp = deps.Progression.addXp(player, XP[key], key)
	payFolios(player, FOLIOS[key], key)
```

  (the rest of `payOne`, from `-- Only the killer's own tally counts a kill`, stays.)
- Before `function Rewards.forget(player: Player)` add

```lua
-- Pays `killer` for taking `victim` down at `now` (D-282), under the pair rule, the bubble and the daily cap. A
-- refused kill is not recorded: only a kill the page could pay starts a pair's wait.
function Rewards.payPlayer(killer: Player, victim: Player, now: number)
	if killer == victim or not Roster.holds(killer) or not Roster.holds(victim) or deps.Combat.isProtected(victim) then
		return
	end
	if not FlyleafRules.recordKill(ledger, killer.UserId, victim.UserId, now, FARM) then
		return
	end
	local xp = deps.Progression.addXp(killer, KILL.Xp, KILL_REASON)
	payFolios(killer, KILL.Folios, KILL_REASON)
	deps.Notify.send(killer, "hud.playerKill", { name = victim.DisplayName, xp = xp }, "Success", "Kill")
end

-- What the pair ledger keeps stays bounded by the kills of the last window. A player who left is not forgotten
-- sooner: rejoining must not wipe the kills they took.
function Rewards.prune(now: number)
	FlyleafRules.prune(ledger, now, FARM)
end
```

3c. `src/server/Services/BattlegroundService/Roster.luau`, before `-- Whether there is a place for `player`: they already hold one, or the page is not full.`:

```lua
-- Whether the page holds `player`: a member, or a member who died inside and whose next body it waits for.
function Roster.holds(player: Player): boolean
	return members[player] ~= nil or pendingRespawn[player.UserId] ~= nil
end
```

3d. `src/server/Services/BattlegroundService/init.luau`:
- In `tick`, right after the `restUntil` clean-up loop and before `judgeFalls(map)`, add `Rewards.prune(now)` (keep `judgeFalls(map)` and `Roster.step(now, dt)` adjacent: `tests/MovementGates.spec.luau` reads them together).
- Replace the comment and the first line of `onKilled`'s body with

```lua
-- Fired inside ApplyDamage, before or after the body's Died: the Forger is found by model either way, dead or
-- not, and credited once. A player's body is a member's kill of another, which Rewards judges (D-282).
local function onKilled(sourceUserId: number, model: Model)
	local victim = Players:GetPlayerFromCharacter(model)
	if victim ~= nil then
		local killer = Players:GetPlayerByUserId(sourceUserId)
		if killer ~= nil then
			log.try("Rewards.payPlayer", Rewards.payPlayer, killer, victim, os.clock())
		end
		return
	end
	local bot = Bots.byModel(model)
```

  (the rest of `onKilled`, from `if bot == nil or bot.Credited then`, stays.)

3e. `src/server/Config/AnalyticsConfig.luau`, in `AnalyticsConfig.Transactions` before the `Spar` comment:

```lua
	-- A member's kill of another on the Battleground, under the Forgers' daily cap (BattlegroundService, D-282).
	BattlegroundKill = "Gameplay",
```

3f. `src/shared/Strings.luau`: the cap is now the page's, not only the Forgers':

```lua
	["battleground.folioCap"] = {
		en = "The battleground pays no more Folios today. XP still counts.",
		fr = "Le champ de bataille ne rapporte plus de Folios aujourd'hui. L'XP compte toujours.",
	},
```

Run: `lune run scripts/export-strings`
Expected: `wrote localization.csv (677 keys)`.

- [ ] **Step 4: Format and run the gates**

Run: `stylua src tests && lune run tests/run 2>&1 | grep -E "✖|passed|failed to load" -A1`
Expected: `0 failed` (2 541 or more passed).
Run: `scripts/check.sh`
Expected: `✔ all quality gates green`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/Config/BattlegroundConfig.luau src/server/Services/BattlegroundService/Rewards.luau src/server/Services/BattlegroundService/Roster.luau src/server/Services/BattlegroundService/init.luau src/server/Config/AnalyticsConfig.luau src/shared/Strings.luau localization.csv tests/Battleground.spec.luau tests/EconomyEvents.spec.luau
git commit -m "feat(battleground): a member's kill pays once per pair, under the daily cap" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Write D-282 into the docs**

`docs/GAME_DESIGN.md`, the line starting `- **Protection de spawn** :` becomes:

```markdown
- **Protection de spawn** : 4 s sans donner ni recevoir de dégâts. Les **zones** disent qui blesse qui (`ZoneConfig`, D-266) : aucun PvP au hub (les mannequins restent frappables), les adversaires d'un même match entre eux, les membres de la Page de garde entre eux hors de leur protection, tous les membres du Champ de bataille entre eux et contre les Faussaires (D-282), jamais entre joueurs de l'Effacement. Au Champ de bataille, l'arrivée et chaque retour après une mort posent une bulle de 3 s à la place : personne ne blesse son porteur, et elle éclate au premier coup qu'il porte.
```

the table row starting `| Champ de bataille (D-131) |` becomes:

```markdown
| Champ de bataille (D-131, D-282) | tous (12 max) | libre | — | XP/Folios par Faussaire vaincu ; 60 XP et 3 Folios par membre vaincu, une fois par paire tueur → victime tant que la paire n'a pas passé 5 min sans kill ; Folios plafonnés à 150/jour en tout ; quête `BotKill` |
```

and the line starting `- **Champ de bataille** (`workspace.Battleground`, D-131)` becomes:

```markdown
- **Champ de bataille** (`workspace.Battleground`, D-131, D-282) : une page de 700×700 à X = 1500, au bord déchiré (une chute tue : `KillZone` 40 studs sous le sol), réglée à l'encre tous les 20 studs avec sa marge ; au centre une estrade de craie de 200×200 haute d'une marche, bordée d'encre, et douze murets d'encre de 6 studs en L et en I ; autour, en os, le Livre ouvert (nord-ouest, gradins jusqu'à 18 studs), la Plume tombée (nord, rampe jusqu'à 40), les Falaises de folios (nord-est, paliers jusqu'à 60), le Lit réglé et le Pont cousu (est), le Champ des sceaux (sud), les Ruines du scriptorium (sud-ouest), le Cratère d'encrier (ouest, quatre brèches) ; le camp au bord ouest (lavis, ligne d'encre à x = −310) avec `Arrival_1..6` et le portail `ReturnPortal` face à l'est, `Arrival_7..18` au pourtour ; `BotSpawn_1..8` à 60 studs au moins de toute arrivée ; les Faussaires dans `workspace.Forgers`, étiquetés `Forger`, restent au sol.
```

`docs/ECONOMY.md`, the row starting `| Faussaires du champ de bataille (D-131) |` becomes:

```markdown
| Champ de bataille (D-131, D-282) : Faussaires et membres vaincus | 1–4 par Faussaire (Barbouilleur, Plume 1 ; Surchargeur 4) ; 3 par membre vaincu (60 XP), une fois par paire tueur → victime tant que la paire n'a pas passé 5 min sans kill | plafond **150 / jour** (profil), commun aux deux | hors du total ci-dessous |
```

`docs/DECISIONS.md`, append after D-281:

```markdown
**D-282 — La Page : un champ de bataille de 700 studs où tous les membres s'affrontent, Faussaires compris** · Demande du développeur (`docs/superpowers/specs/2026-10-09-battleground-page-design.md`) · hypothèses décidées en autonomie, à confirmer par le développeur
Le champ de bataille de 170 studs (D-131) devient une page de 700 × 700 à X = 1500, bâtie en code par `BattlegroundLayout` à partir de `BattlegroundConfig.Map` avec des pièces simples (blocs, coins, cylindres) tournées autour de la verticale : un bord déchiré (une bande de 10 studs en languettes de 20, déchirées de 0 à 8 studs), la réglure tous les 20 studs et sa marge, le camp et son portail au bord ouest, une estrade de craie de 200 × 200 haute d'une marche avec douze murets d'encre de 6 studs, et sept repères en os (le Livre ouvert, la Plume tombée, les Falaises de folios jusqu'à 60 studs, le Lit réglé et le Pont cousu, le Champ des sceaux, les Ruines du scriptorium, le Cratère d'encrier). L'empreinte au sol d'une pièce tournée est un rectangle orienté ; le graphe des Faussaires (un nœud tous les 20 studs, jusqu'à 30 studs du bord) les contourne exactement, et un Faussaire ne poursuit personne au-delà. Dix-huit arrivées : six au camp, douze au pourtour, à 80 studs au moins les unes des autres et à 60 des apparitions des Faussaires. Un membre le reste jusqu'à 80 studs au-dessus du sol (un saut depuis le plus haut palier) ; les fosses du duel d'épreuve reculent à x = 650 du repère de la page, hors de portée des paquets et du plan de mort, ramené à 1,5 fois la page. Tous les membres se blessent : la page tient la zone `Battleground` de `ZoneConfig` (D-266), où les Faussaires restent frappables et où `CombatService` ne paie pas lui-même les kills. L'arrivée et chaque retour après une mort posent une bulle de 3 s (`CombatService.protect`) : personne ne blesse son porteur, et elle éclate au premier coup qu'il porte ; elle retire le `ForceField` que le `SpawnLocation` du hub laisse sur un corps qui réapparaît ; ailleurs, la protection de spawn ne change pas. Un kill d'un membre par un autre paie 60 XP et 3 Folios, ces derniers sous le plafond quotidien des Faussaires (150, `Daily.ForgerFolios`), une fois par paire tueur → victime ; rien pour une victime sous sa bulle, ni pour un tueur ou une victime que la page ne tient pas (un membre, ou un membre mort à l'intérieur dont elle attend le corps).
Raison : le développeur veut une grande carte où tout le monde s'affronte, comme les battlegrounds Roblox actuels, avec un anti-farm simple. À confirmer : (1) le Lit réglé est dessiné à plat et non creusé de 3 studs : creusé, un membre couché au fond passerait sous `BoundsDepthStuds` (0,5), que tient la portée des coups des Faussaires (`tests/BotBrain.spec.luau`), et la page le lâcherait ; (2) sans murs, une chute tue ; (3) 60 XP et 3 Folios par kill ; (4) la fenêtre de 300 s d'une paire repart de chaque kill, payé ou non (le registre de la Page de garde, `FlyleafRules.recordKill`, une mort payée par fenêtre) : deux joueurs qui s'entretuent sans arrêt ne sont payés qu'une fois ; (5) un coup dans le vide ne fait pas éclater la bulle, qui tombe au premier coup qui atteint `ApplyDamage` ; (6) les arrivées sont prises à tour de rôle, sans viser la plus éloignée des autres membres ; (7) restent hors du lot la bulle visible, le verrou sur les autres membres et un toast pour un kill non payé. `tests/BattlegroundLayout.spec.luau`, `tests/DamageZones.spec.luau`, `tests/Battleground.spec.luau`.
```

`docs/PROGRESS.md`, append at the end:

```markdown
## La Page, le grand Champ de bataille (D-282) — 9 octobre 2026

**Fait.** Sur `feat/battleground-page`, d'après la spécification `docs/superpowers/specs/2026-10-09-battleground-page-design.md` et son plan `docs/superpowers/plans/2026-10-09-battleground-page.md` : le Champ de bataille passe de 170 à 700 studs, bord déchiré, estrade centrale et sept repères en pièces simples, la grille des Faussaires à 20 studs ; tous les membres s'affrontent, derrière une bulle de 3 s à l'arrivée et à chaque retour, qui éclate au premier coup ; un kill d'un membre paie 60 XP et 3 Folios, une fois par paire et par 5 min, sous le plafond quotidien des Faussaires. `scripts/check.sh` vert à chaque commit.

**Reste, dans Studio.** Voir la carte construite : chaque coin monte dans le bon sens (un `WedgePart` monte vers son +z), chaque sceau est debout, un Faussaire franchit la marche de l'estrade ; jouer à deux clients (la bulle, le premier coup qui la fait tomber, un kill payé puis le même refusé) ; mesurer la carte sur mobile avant de décider du streaming.

**À confirmer par le développeur.** Les hypothèses (1) à (7) de D-282.
```

- [ ] **Step 7: Run the gates and commit the docs**

Run: `scripts/check.sh`
Expected: `✔ all quality gates green` (`tests/Lexicon.spec.luau` scans `docs/`).

```bash
git add docs/GAME_DESIGN.md docs/ECONOMY.md docs/DECISIONS.md docs/PROGRESS.md
git commit -m "docs(battleground): D-282, the Page in the design, economy and progress" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
