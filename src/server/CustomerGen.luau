--!strict
-- Random customer generator. Rolls a hidden profile (wallet, taste, price
-- attitude, patience) plus a visible cue (age, situation) from the pack's
-- CustomerSpec. Pack-agnostic: it only reads the spec.

local Types = require(game.ReplicatedStorage.Shared.Types)

type Pack = Types.Pack
type CustomerProfile = Types.CustomerProfile
type AgeGroup = Types.AgeGroup

local CustomerGen = {}

local nextId = 0

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function pickWeighted(rng: Random, groups: { AgeGroup }): AgeGroup
	local total = 0
	for _, group in groups do
		total += group.weight
	end
	local roll = rng:NextNumber() * total
	for _, group in groups do
		roll -= group.weight
		if roll <= 0 then
			return group
		end
	end
	return groups[#groups]
end

-- `buzz` scales the wallet (word of mouth from earlier customers' stars).
-- `avoidName` keeps the same name from appearing twice in a row.
function CustomerGen.generate(pack: Pack, rng: Random, buzz: number, avoidName: string?): CustomerProfile
	local spec = pack.customers
	local age = pickWeighted(rng, spec.ageGroups)

	local name = pick(rng, spec.names)
	for _ = 1, 4 do
		if name ~= avoidName then
			break
		end
		name = pick(rng, spec.names)
	end

	local baseWallet = rng:NextInteger(age.budgetMin, age.budgetMax)
	local wallet = math.max(1, math.floor(baseWallet * buzz + 0.5))

	nextId += 1
	return {
		id = nextId,
		name = name,
		look = pick(rng, spec.looks),
		ageGroup = age.label,
		situation = pick(rng, spec.situations),
		taste = pick(rng, spec.tastes),
		sensitivity = pick(rng, spec.sensitivities),
		wallet = wallet,
		patience = rng:NextInteger(spec.patienceMin, spec.patienceMax),
	}
end

-- The only slice of a profile the client is allowed to see.
function CustomerGen.visible(profile: CustomerProfile): { [string]: any }
	return {
		id = profile.id,
		name = profile.name,
		ageGroup = profile.ageGroup,
		situation = profile.situation,
	}
end

return CustomerGen
