--!strict
-- SoundConfig is the seam between the audio generators and the client, and it can rot on both sides:
-- a WAV renamed on disk while the config names the old file, or a length written into the config that
-- the file does not have -- and a boss warning is stretched to its window from that length, so a wrong
-- number is a warning that ends before the hit.
--
-- So the config is checked against the files' own headers, the way tests/AssetIds.spec.luau reads the
-- PNGs. It is the only test that reads the generated audio.
local Harness = require("./harness")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local SoundConfig = require("../src/shared/Config/SoundConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- The two rates the generators write at (tools/audio/vellum_wav.py). A file at any other rate came from
-- somewhere else, which is the one provenance this game does not allow.
local RATES: { [number]: boolean } = { [22050] = true, [16000] = true }

-- RIFF header: "RIFF", size, "WAVE", then the fmt chunk this writer always puts first at offset 12.
local function wavInfo(path: string): (number, number, number, number)
	local bytes = fs.readFile(path)
	assert(string.sub(bytes, 1, 4) == "RIFF" and string.sub(bytes, 9, 12) == "WAVE", path .. " is not a WAV")
	assert(string.sub(bytes, 13, 16) == "fmt ", path .. " does not start with a fmt chunk")
	local channels = string.unpack("<I2", bytes, 23)
	local rate = string.unpack("<I4", bytes, 25)
	local bits = string.unpack("<I2", bytes, 35)
	assert(string.sub(bytes, 37, 40) == "data", path .. " has no data chunk where the writer puts one")
	local dataSize = string.unpack("<I4", bytes, 41)
	return rate, channels, bits, dataSize / (rate * channels * (bits / 8))
end

local function eachEntry(fn: (key: string, entry: SoundConfig.SoundEntry, music: boolean) -> ())
	for key, entry in pairs(SoundConfig.Sfx) do
		fn(key, entry, false)
	end
	for key, entry in pairs(SoundConfig.Music) do
		fn(key, entry, true)
	end
end

describe("SoundConfig", function()
	it("declares something, so nothing below passes vacuously", function()
		local count = 0
		eachEntry(function()
			count += 1
		end)
		expect(count).toBeGreaterThanOrEqual(50)
	end)

	it("points every entry at a generated file that exists", function()
		local wrong: { string } = {}
		eachEntry(function(key, entry)
			if not string.match(entry.Source, "^assets/audio/[%w_]+%.wav$") then
				table.insert(wrong, ("%s has source %q, which is not a generated audio path"):format(key, entry.Source))
			elseif not fs.isFile(entry.Source) then
				table.insert(wrong, ("%s names %s, which does not exist"):format(key, entry.Source))
			end
		end)
		table.sort(wrong)
		if #wrong > 0 then
			error(table.concat(wrong, "\n"))
		end
	end)

	it("declares the length and shape the file actually has", function()
		local wrong: { string } = {}
		eachEntry(function(key, entry, music)
			if not fs.isFile(entry.Source) then
				return
			end
			local rate, channels, bits, seconds = wavInfo(entry.Source)
			if not RATES[rate] or channels ~= 1 or bits ~= 16 then
				table.insert(wrong, ("%s is %d Hz, %d channel(s), %d bits"):format(key, rate, channels, bits))
			end
			if math.abs(seconds - entry.Seconds) > 0.011 then
				table.insert(wrong, ("%s says %.2fs, the file is %.2fs"):format(key, entry.Seconds, seconds))
			end
			-- A loop is long and an effect is short; the two rates say which is which.
			if music and rate ~= 16000 then
				table.insert(wrong, ("%s is music at %d Hz"):format(key, rate))
			end
		end)
		table.sort(wrong)
		if #wrong > 0 then
			error(table.concat(wrong, "\n"))
		end
	end)

	it("keeps every number usable", function()
		eachEntry(function(_, entry, music)
			expect(entry.Volume > 0 and entry.Volume <= 1).toBe(true)
			expect(entry.Speed > 0).toBe(true)
			-- The plan's five percent is the ceiling: past it a repeat stops sounding like the same thing.
			expect(entry.Vary >= 0 and entry.Vary <= 0.05).toBe(true)
			if music then
				-- A loop that wanders in pitch is a loop that is out of tune with the sequence notes.
				expect(entry.Vary).toBe(0)
			end
		end)
	end)

	it("has all four voices for every pigment", function()
		-- A timeline names a voice and the renderer names the pigment; a pigment missing one voice is a
		-- glyph whose landing is silent, found only by casting it.
		for _, pigment in ipairs(PigmentConfig.Order) do
			for _, voice in ipairs(SoundConfig.Voices) do
				local key = SoundConfig.voiceKey(pigment, voice)
				if SoundConfig.Sfx[key] == nil then
					error(("pigment %s has no %s voice (%s)"):format(pigment, voice, key))
				end
			end
			if SoundConfig.Sfx["Note" .. pigment] == nil then
				error(("pigment %s has no sequence note"):format(pigment))
			end
		end
	end)

	it("lists exactly what still has to be uploaded, in a stable order", function()
		local missing = SoundConfig.missing()
		local expected = 0
		eachEntry(function(_, entry)
			if entry.Id == "" then
				expected += 1
			end
		end)
		expect(#missing).toBe(expected)
		for index = 2, #missing do
			if missing[index] < missing[index - 1] then
				error("missing() is not sorted, so its warning changes order between runs")
			end
		end
	end)

	it("never carries an id that is not a Roblox content id", function()
		eachEntry(function(key, entry)
			if entry.Id ~= "" and string.match(entry.Id, "^rbxassetid://%d+$") == nil then
				error(("%s has id %q, which is not rbxassetid://<number>"):format(key, entry.Id))
			end
		end)
	end)
end)
