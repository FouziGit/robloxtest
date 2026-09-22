--!strict
-- Feel owns the camera. Nothing else may write to it.
--
-- This is not style. Two systems writing CurrentCamera in the same frame produce a camera that depends
-- on which render binding happened to run second, which is why the previous version could leave the
-- field of view permanently wrong: VfxController pulsed it with two chained tweens, and two hits landing
-- in the same frame left one tween's end value as the new resting state. It also produced a camera that
-- jittered with math.random on its own RenderStepped while another effect faded a shake, and the two
-- offsets fought.
--
-- The rule is checked at the source level because there is no other way: nothing in a Lune test can hold
-- a Camera, and the failure only shows up on a machine running the game.
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local OWNER = "src/client/Controllers/Feel.luau"
local ROOTS = { "src/client", "src/ui" }

-- Writing any of these is taking over the camera.
local CAMERA_WRITES = {
	"%.FieldOfView%s*=",
	"CurrentCamera%.CFrame%s*=",
	"camera%.CFrame%s*=",
	-- Who the camera is looking at is the camera too. SpectateController asks Feel to change it (Feel.watch)
	-- rather than setting it: a second writer would fight the respawn the engine performs on its own, and
	-- the player would end a round watching a corpse or a stranger.
	"CameraSubject%s*=",
}

-- Hit-stop, shake and the field of view are one mechanism with one owner. A controller that reaches for
-- the engine directly instead of calling Feel is how the second owner appears.
local DIRECT_CAMERA_OFFSET = { "CameraOffset%s*=" }

local function collect(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			collect(path, out)
		elseif string.match(entry, "%.luau$") then
			table.insert(out, path)
		end
	end
end

local function stripComments(source: string): string
	local withoutBlocks = string.gsub(source, "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function offenders(patterns: { string }): { string }
	local files: { string } = {}
	for _, root in ipairs(ROOTS) do
		collect(root, files)
	end
	assert(#files > 10, "found almost no client files: the roots are wrong")

	local found: { string } = {}
	for _, path in ipairs(files) do
		if path ~= OWNER then
			local code = stripComments(fs.readFile(path))
			for _, pattern in ipairs(patterns) do
				if string.find(code, pattern) ~= nil then
					table.insert(found, ("%s matches %s"):format(path, pattern))
				end
			end
		end
	end
	table.sort(found)
	return found
end

describe("camera ownership", function()
	it("is Feel's alone", function()
		local found = offenders(CAMERA_WRITES)
		if #found > 0 then
			error("only " .. OWNER .. " may write the camera:\n" .. table.concat(found, "\n"))
		end
	end)

	it("leaves Humanoid.CameraOffset alone everywhere", function()
		-- The old shake moved the camera through the Humanoid, which the engine also writes when the
		-- character crouches or is on a seat, so the two overwrote each other and a shake could stick.
		local found = offenders(DIRECT_CAMERA_OFFSET)
		if #found > 0 then
			error("camera shake goes through Feel, not Humanoid.CameraOffset:\n" .. table.concat(found, "\n"))
		end
	end)

	it("actually writes the camera in the owner, so this test cannot pass vacuously", function()
		local owner = stripComments(fs.readFile(OWNER))
		expect(string.find(owner, "%.FieldOfView%s*=") ~= nil).toBe(true)
		expect(string.find(owner, "camera%.CFrame%s*=") ~= nil).toBe(true)
		expect(string.find(owner, "CameraSubject%s*=") ~= nil).toBe(true)
	end)
end)
