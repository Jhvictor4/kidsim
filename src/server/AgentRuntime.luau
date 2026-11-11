--!strict
-- The three personas: counterpart (in-world NPC), coach (hint, never the
-- answer), evaluator (structured debrief JSON). All prompts come from the
-- pack's `cast` — this module stays pack-agnostic.

local HttpService = game:GetService("HttpService")

local LlmClient = require(script.Parent.LlmClient)
local Config = require(script.Parent.Config)
local Types = require(game.ReplicatedStorage.Shared.Types)

type Pack = Types.Pack
type PackEvent = Types.PackEvent
type LogEntry = Types.LogEntry
type Evaluation = Types.Evaluation

local AgentRuntime = {}

local function stateSummary(pack: Pack, state: { meters: { [string]: number }, inventory: { [string]: number } }): string
	local parts = {}
	for _, meter in pack.meters do
		table.insert(parts, meter.label .. "=" .. tostring(state.meters[meter.key] or 0))
	end
	local inv = {}
	for key, count in state.inventory do
		local label = pack.inventoryLabels[key] or key
		table.insert(inv, label .. " x" .. tostring(count))
	end
	table.sort(inv)
	return table.concat(parts, ", ") .. "; stock: " .. table.concat(inv, ", ")
end

-- ========== Counterpart ==========

function AgentRuntime.counterpartReply(
	pack: Pack,
	event: PackEvent,
	state: { meters: { [string]: number }, inventory: { [string]: number } },
	history: { LlmClient.ChatMessage },
	playerText: string
): string
	local system = table.concat({
		pack.cast.counterpartBase,
		"You are playing this character: " .. event.counterpart.persona,
		"Scene facts (do not contradict these): " .. event.context,
		"Current world state: " .. stateSummary(pack, state),
	}, "\n\n")

	-- `history` already ends with the player's latest line (the engine appends
	-- it before calling us); appending playerText again would send duplicate
	-- user turns, which strict chat-template endpoints reject.
	local messages: { LlmClient.ChatMessage } = { { role = "system", content = system } }
	for _, msg in history do
		table.insert(messages, msg)
	end

	local ok, reply = LlmClient.chat(messages, { maxTokens = Config.MAX_TOKENS_DIALOGUE, temperature = 0.8 })
	if ok then
		-- keep it bubble-sized even if the model rambles
		if #reply > 300 then
			reply = string.sub(reply, 1, 297) .. "..."
		end
		return reply
	end
	return "Hmm... anyway — what do you say to my request?"
end

-- ========== Coach ==========

function AgentRuntime.coachHint(
	pack: Pack,
	event: PackEvent,
	state: { meters: { [string]: number }, inventory: { [string]: number } }
): string
	local system = table.concat({
		pack.cast.coach,
		"Current situation: " .. event.title .. ". " .. event.context,
		"Private coaching note (nudge toward this WITHOUT revealing the exact best choice): " .. event.coachNote,
		"World state: " .. stateSummary(pack, state),
	}, "\n\n")

	local ok, reply = LlmClient.chat({
		{ role = "system", content = system },
		{ role = "user", content = "Give me one short hint." },
	}, { maxTokens = 80, temperature = 0.6 })

	if ok then
		if #reply > 200 then
			reply = string.sub(reply, 1, 197) .. "..."
		end
		return reply
	end
	return "Think about what this decision does to your numbers, not just to this one person."
end

-- ========== Evaluator ==========

local EVAL_SCHEMA = [[Reply with ONLY a JSON object, no prose, no markdown fences, exactly this shape:
{
  "skills": [{"tag": "skill_tag", "name": "Plain-English skill name", "evidence": "one sentence citing what the player actually did"}],
  "wentWell": ["short bullet", "..."],
  "wentWrong": ["short bullet", "..."],
  "realWorldTransfer": "one sentence: what this practice is called in real life and where the child will meet it",
  "nextDrill": "one concrete thing to practice next shift"
}]]

local function tryParseEvaluation(raw: string): Evaluation?
	-- strip code fences and grab the outermost object
	local cleaned = raw:gsub("```json", ""):gsub("```", "")
	local first = cleaned:find("{")
	local last = cleaned:match(".*()}")
	if not first or not last then
		return nil
	end
	cleaned = cleaned:sub(first :: number, last :: number)

	local ok, data = pcall(function()
		return HttpService:JSONDecode(cleaned)
	end)
	if not ok or typeof(data) ~= "table" then
		return nil
	end
	if typeof(data.skills) ~= "table" or typeof(data.realWorldTransfer) ~= "string" or typeof(data.nextDrill) ~= "string" then
		return nil
	end

	-- Coerce element shapes so a legal-JSON-wrong-shape reply can never
	-- error the client's debrief renderer.
	local function toStringList(value: any): { string }
		if typeof(value) ~= "table" then
			return {}
		end
		local list = {}
		for _, item in value do
			if typeof(item) == "string" then
				table.insert(list, item)
			elseif typeof(item) == "table" then
				for _, nested in item do
					if typeof(nested) == "string" then
						table.insert(list, nested)
						break
					end
				end
			end
		end
		return list
	end
	local skills = {}
	for _, skill in data.skills do
		if typeof(skill) == "table" then
			table.insert(skills, {
				tag = typeof(skill.tag) == "string" and skill.tag or "skill",
				name = typeof(skill.name) == "string" and skill.name or tostring(skill.tag or "Skill"),
				evidence = typeof(skill.evidence) == "string" and skill.evidence or "",
			})
		end
	end
	data.skills = skills
	data.wentWell = toStringList(data.wentWell)
	data.wentWrong = toStringList(data.wentWrong)
	return data :: Evaluation
end

local function fallbackEvaluation(pack: Pack, log: { LogEntry }): Evaluation
	local skills = {}
	local seen: { [string]: boolean } = {}
	for _, entry in log do
		if entry.lessonTag and not seen[entry.lessonTag] then
			seen[entry.lessonTag] = true
			table.insert(skills, {
				tag = entry.lessonTag,
				name = (entry.lessonTag:gsub("_", " "):gsub("^%l", string.upper)),
				evidence = entry.logLine,
			})
		end
	end
	local wentWell = {}
	for _, entry in log do
		table.insert(wentWell, entry.logLine)
	end
	return {
		skills = skills,
		wentWell = wentWell,
		wentWrong = {},
		realWorldTransfer = "You just practiced running a small business: money in, stock out, people happy.",
		nextDrill = "Next shift, try to end with MORE cash and the SAME reputation.",
	}
end

function AgentRuntime.evaluate(
	pack: Pack,
	initialState: { meters: { [string]: number }, inventory: { [string]: number } },
	finalState: { meters: { [string]: number }, inventory: { [string]: number } },
	log: { LogEntry }
): Evaluation
	local system = table.concat({
		pack.cast.evaluator,
		"Skill tags available for this scenario: " .. table.concat(pack.skillTags, ", "),
		pack.debriefTemplate,
		EVAL_SCHEMA,
	}, "\n\n")

	local payload = HttpService:JSONEncode({
		scenario = pack.title,
		initialState = initialState,
		finalState = finalState,
		shiftLog = log,
	})

	local messages: { LlmClient.ChatMessage } = {
		{ role = "system", content = system },
		{ role = "user", content = "Here is the full shift record. Evaluate it.\n" .. payload },
	}

	for attempt = 1, 2 do
		local ok, reply = LlmClient.chat(messages, { maxTokens = Config.MAX_TOKENS_EVALUATION, temperature = 0.3 })
		if ok then
			local parsed = tryParseEvaluation(reply)
			if parsed then
				return parsed
			end
			table.insert(messages, { role = "assistant", content = reply })
			table.insert(messages, {
				role = "user",
				content = "That was not valid JSON. Reply again with ONLY the JSON object.",
			})
		else
			break
		end
		if attempt == 1 then
			task.wait(0.5)
		end
	end

	warn("[KidSim] Evaluator fell back to deterministic debrief")
	return fallbackEvaluation(pack, log)
end

return AgentRuntime
