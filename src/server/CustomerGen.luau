--!strict
-- Random people generator. Rolls customers (hidden wallet, taste, price
-- attitude, patience + a visible cue) and staff (hidden personality) from
-- the pack's specs, each with its own text-to-speech voice. Pack-agnostic.

local Types = require(game.ReplicatedStorage.Shared.Types)
local Config = require(script.Parent.Config)

type Pack = Types.Pack
type CustomerProfile = Types.CustomerProfile
type StaffProfile = Types.StaffProfile
type AgeGroup = Types.AgeGroup
type Personality = Types.Personality
type Voice = Types.Voice

local CustomerGen = {}

local nextId = 0

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function pickWeighted<T>(rng: Random, items: { T }, weightOf: (T) -> number): T
	local total = 0
	for _, item in items do
		total += weightOf(item)
	end
	local roll = rng:NextNumber() * total
	for _, item in items do
		roll -= weightOf(item)
		if roll <= 0 then
			return item
		end
	end
	return items[#items]
end

local PITCH_BY_AGE: { [string]: number } = { kid = 5, teen = 2, adult = 0, senior = -2 }

local function rollVoice(rng: Random, ageGroup: string?): Voice
	local base = PITCH_BY_AGE[ageGroup or "adult"] or 0
	return {
		voiceId = pick(rng, Config.TTS_VOICES),
		pitch = math.clamp(base + rng:NextNumber(-1.5, 1.5), -12, 12),
		speed = rng:NextNumber(0.95, 1.15),
	}
end

-- `buzz` scales the wallet (word of mouth from earlier customers' stars).
-- `pressure` makes half the customers ones that push staff toward rule breaks
-- (used when memory says the owner missed problem staff last round).
function CustomerGen.customer(pack: Pack, rng: Random, buzz: number, pressure: boolean?): CustomerProfile
	local spec = pack.customers
	local age = pickWeighted(rng, spec.ageGroups, function(g: AgeGroup)
		return g.weight
	end)
	local wallet = math.max(1, math.floor(rng:NextInteger(age.budgetMin, age.budgetMax) * buzz + 0.5))
	nextId += 1
	return {
		id = nextId,
		name = pick(rng, spec.names),
		look = pick(rng, spec.looks),
		ageGroup = age.label,
		situation = pick(rng, spec.situations),
		taste = pick(rng, spec.tastes),
		sensitivity = (function()
			if pressure and rng:NextNumber() < 0.5 then
				for _, s in spec.sensitivities do
					if s.pressure then
						return s
					end
				end
			end
			return pick(rng, spec.sensitivities)
		end)(),
		wallet = wallet,
		patience = rng:NextInteger(spec.patienceMin, spec.patienceMax),
		voice = rollVoice(rng, age.label),
	}
end

-- `taken` = names already on the team; `avoidLabels` = personalities to skip
-- (used to guarantee the first team has at least one problem staff member).
function CustomerGen.staff(pack: Pack, rng: Random, taken: { [string]: boolean }, avoidLabels: { [string]: boolean }?): StaffProfile
	local spec = pack.staff
	local name = pick(rng, spec.names)
	for _ = 1, 20 do
		if not taken[name] then
			break
		end
		name = pick(rng, spec.names)
	end
	local pool = {}
	for _, p in spec.personalities do
		if not (avoidLabels and avoidLabels[p.label]) then
			table.insert(pool, p)
		end
	end
	if #pool == 0 then
		pool = spec.personalities
	end
	nextId += 1
	return {
		id = nextId,
		name = name,
		look = pick(rng, spec.looks),
		personality = pickWeighted(rng, pool, function(p: Personality)
			return p.weight
		end),
		voice = rollVoice(rng, "adult"),
	}
end

return CustomerGen
