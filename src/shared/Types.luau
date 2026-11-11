--!strict
-- Scenario pack contract. The engine knows ONLY these shapes — nothing
-- cafe-specific. A pack supplies a menu, a stock, rules for generating
-- random customers, and the persona prompts. Every customer is an agent:
-- the child talks, the customer decides what to buy and how happy it is.

export type MenuItem = {
	key: string, -- stock key, e.g. "coffee"
	label: string, -- what the HUD / menu board prints
	price: number, -- menu price in whole dollars
}

export type AgeGroup = {
	label: string, -- "kid", "teen", "adult", "senior"
	budgetMin: number,
	budgetMax: number,
	weight: number, -- relative spawn weight
}

export type Sensitivity = {
	label: string, -- shown nowhere; prompt flavour only
	prompt: string, -- how this customer feels about prices and upsells
}

export type CustomerSpec = {
	names: { string },
	looks: { string }, -- colour names the world builder understands
	ageGroups: { AgeGroup },
	situations: { string }, -- the visible cue the shopkeeper can read
	tastes: { string }, -- hidden: what actually tempts them
	sensitivities: { Sensitivity },
	patienceMin: number, -- how many player lines before they must decide
	patienceMax: number,
}

-- One generated customer. `wallet`, `taste`, `sensitivity` are hidden from
-- the client; the server only ever sends the visible slice.
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
}

export type Pack = {
	id: string,
	title: string,
	thesis: string, -- the one-line product thesis shown in the lobby
	briefing: string, -- what the player is about to do
	skillTags: { string },
	menu: { MenuItem },
	initialStock: { [string]: number }, -- per player, per round
	customers: CustomerSpec,
	cast: {
		customerBase: string, -- guardrails shared by every customer
		coach: string,
		evaluator: string,
	},
	debriefTemplate: string, -- evaluator guidance for sim-to-real transfer
}

-- What a customer agent decided this turn (after server validation).
export type CustomerTurn = {
	say: string,
	decision: string, -- "stay" | "buy" | "leave"
	items: { [string]: number },
	pay: number,
	stars: number, -- 1..5, only meaningful on buy/leave
}

export type SaleRecord = {
	customer: string,
	ageGroup: string,
	situation: string,
	taste: string,
	sensitivity: string,
	wallet: number,
	playerSaid: { string },
	outcome: string, -- "bought" | "left" | "timeout"
	items: { [string]: number },
	paid: number,
	menuValue: number, -- menu price of what they took
	stars: number,
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
	lane: number,
	revenue: number,
	avgStars: number,
	served: number,
	score: number,
}

return {}
