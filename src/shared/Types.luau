--!strict
-- Scenario pack contract. The engine knows ONLY these shapes — nothing
-- cafe-specific. A new pack (court, negotiation, accounting) is a new
-- module returning a Pack; engine code does not change.

export type MeterDef = {
	key: string, -- generic state key, e.g. "cash", "reputation"
	label: string, -- what the HUD prints
	format: string, -- "currency" | "number" | "score"
	max: number?, -- optional clamp ceiling (e.g. reputation 100)
}

export type Deltas = {
	meters: { [string]: number }?,
	inventory: { [string]: number }?,
}

export type Choice = {
	id: string,
	label: string,
	deltas: Deltas,
	-- inventory needed for this choice to be offered (engine filters)
	requires: { [string]: number }?,
	reaction: string, -- counterpart's scripted closing line
	logLine: string, -- what the shift log records (evaluator reads this)
	lessonTag: string?, -- which skillTag this choice exercises
}

export type PackEvent = {
	id: string,
	title: string,
	counterpart: {
		name: string,
		look: string?, -- hint for the world builder (color name)
		persona: string, -- system prompt fragment for the counterpart LLM
	},
	opening: string, -- scripted first line (never depends on the LLM)
	context: string, -- scene facts handed to the LLM
	coachNote: string, -- what the coach may nudge toward (not the answer)
	choices: { Choice },
}

export type Pack = {
	id: string,
	title: string,
	thesis: string, -- the one-line product thesis shown at Intro
	briefing: string, -- what the player is about to do
	skillTags: { string },
	meters: { MeterDef },
	inventoryLabels: { [string]: string },
	initialState: {
		meters: { [string]: number },
		inventory: { [string]: number },
	},
	menuText: string?, -- optional world dressing (menu board etc.)
	cast: {
		counterpartBase: string, -- guardrails shared by all counterparts
		coach: string,
		evaluator: string,
	},
	events: { PackEvent },
	debriefTemplate: string, -- evaluator guidance for sim-to-real transfer
}

export type LogEntry = {
	eventId: string,
	eventTitle: string,
	playerSaid: { string },
	choiceId: string,
	logLine: string,
	lessonTag: string?,
}

export type Evaluation = {
	skills: { { tag: string, name: string, evidence: string } },
	wentWell: { string },
	wentWrong: { string },
	realWorldTransfer: string,
	nextDrill: string,
}

return {}
