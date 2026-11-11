--!strict
-- Scenario pack contract. The engine knows ONLY these shapes — nothing
-- cafe-specific.
--
-- The player is the OWNER. Staff agents serve customer agents at the
-- counters; the owner sets the rules, answers staff questions, and
-- praises, warns or fires staff based on what they see.

export type MenuItem = {
	key: string, -- stock key, e.g. "coffee"
	label: string, -- what the HUD / menu board prints
	price: number, -- menu price in whole dollars
}

export type Voice = {
	voiceId: string, -- AudioTextToSpeech.VoiceId
	pitch: number, -- semitones, -12..12
	speed: number, -- 0.5..2
}

export type AgeGroup = {
	label: string, -- "kid", "teen", "adult", "senior"
	budgetMin: number,
	budgetMax: number,
	weight: number, -- relative spawn weight
}

export type Sensitivity = {
	label: string,
	prompt: string, -- how this customer feels about prices and upsells
}

export type CustomerSpec = {
	names: { string },
	looks: { string }, -- colour names the world builder understands
	ageGroups: { AgeGroup },
	situations: { string }, -- the visible cue
	tastes: { string }, -- hidden: what actually tempts them
	sensitivities: { Sensitivity },
	patienceMin: number, -- staff lines before they must decide
	patienceMax: number,
}

export type CustomerProfile = {
	id: number,
	name: string,
	look: string,
	ageGroup: string,
	situation: string,
	taste: string,
	sensitivity: Sensitivity,
	wallet: number,
	patience: number,
	voice: Voice,
}

-- A hidden staff personality. The owner never sees `label` until the
-- debrief; they have to read it from behaviour.
export type Personality = {
	label: string, -- "Star", "Pushover", ...
	prompt: string, -- how this staff member really behaves
	weight: number,
}

export type StaffSpec = {
	names: { string },
	looks: { string },
	personalities: { Personality },
}

export type StaffProfile = {
	id: number,
	name: string,
	look: string,
	personality: Personality,
	voice: Voice,
}

-- One owner rule. Machine fields let the engine check rule breaks.
export type PolicyOption = {
	label: string, -- shown on the rule chip
	prompt: string, -- what staff are told
	maxDiscountPct: number?, -- discount above this = rule break
	askAboveDiscountPct: number?, -- discount above this without asking = rule break
}

export type Policy = {
	key: string,
	title: string,
	options: { PolicyOption },
	default: number,
}

export type Pack = {
	id: string,
	title: string,
	thesis: string,
	briefing: string,
	skillTags: { string },
	menu: { MenuItem },
	initialStock: { [string]: number }, -- per shop, per round
	customers: CustomerSpec,
	staff: StaffSpec,
	policies: { Policy },
	cast: {
		customerBase: string, -- guardrails shared by every customer
		staffBase: string, -- guardrails shared by every staff member
		evaluator: string,
	},
	debriefTemplate: string,
}

-- What a customer agent decided this turn.
export type CustomerTurn = {
	say: string,
	decision: string, -- "stay" | "buy" | "leave"
	items: { [string]: number },
	pay: number,
	stars: number,
	complaint: string?, -- short reason when unhappy
}

-- What a staff agent decided this turn.
export type StaffTurn = {
	say: string,
	action: string, -- "talk" | "ask_owner"
	question: string?,
	options: { string },
}

export type SaleRecord = {
	staff: string,
	customer: string,
	ageGroup: string,
	situation: string,
	wallet: number,
	outcome: string, -- "bought" | "left"
	items: { [string]: number },
	paid: number,
	menuValue: number,
	discountPct: number,
	stars: number,
	complaint: string?,
	askedOwner: boolean,
	ruleBreaks: { string },
}

-- Everything the owner did, for the evaluator.
export type OwnerEvent = {
	t: number, -- seconds into the round
	kind: string, -- "policy" | "answer" | "unanswered" | "praise" | "warn" | "fire" | "hire"
	staff: string?,
	detail: string,
}

export type Evaluation = {
	skills: { { tag: string, name: string, evidence: string } },
	wentWell: { string },
	wentWrong: { string },
	realWorldTransfer: string,
	nextDrill: string,
}

export type LeaderboardRow = {
	userId: number,
	name: string,
	shop: number,
	revenue: number,
	avgStars: number,
	served: number,
	score: number,
}

return {}
