--!strict
-- The three personas: customer (a generated agent that decides what to buy
-- and how happy it is), coach (one hint, never the answer), evaluator
-- (structured debrief JSON). All prompt text comes from the pack — this
-- module stays pack-agnostic. Everything the customer "decides" is only a
-- proposal: LaneEngine validates it against menu, stock and wallet.

local HttpService = game:GetService("HttpService")

local LlmClient = require(script.Parent.LlmClient)
local Config = require(script.Parent.Config)
local Types = require(game.ReplicatedStorage.Shared.Types)

type Pack = Types.Pack
type CustomerProfile = Types.CustomerProfile
type CustomerTurn = Types.CustomerTurn
type SaleRecord = Types.SaleRecord
type Evaluation = Types.Evaluation

local AgentRuntime = {}

-- ---------- shared helpers ----------

local function menuText(pack: Pack): string
	local lines = {}
	for _, item in pack.menu do
		table.insert(lines, string.format("%s (key \"%s\"): $%d", item.label, item.key, item.price))
	end
	return table.concat(lines, "; ")
end

-- Grab the outermost {...} from a model reply and decode it.
local function decodeObject(raw: string): { [string]: any }?
	local cleaned = raw:gsub("```json", ""):gsub("```", "")
	local first = cleaned:find("{")
	local last = cleaned:match(".*()}")
	if not first or not last then
		return nil
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(cleaned:sub(first :: number, last :: number))
	end)
	if ok and typeof(data) == "table" then
		return data
	end
	return nil
end

local function clip(text: string, limit: number): string
	if #text > limit then
		return string.sub(text, 1, limit - 3) .. "..."
	end
	return text
end

-- ========== Customer ==========

-- The stage direction that makes the customer speak first. LaneEngine seeds
-- the conversation history with it so later turns start with a user message
-- (some chat templates reject an assistant-first history).
AgentRuntime.OPENING_PROMPT =
	"(You just walked up to the counter. Greet the shopkeeper and say roughly what you're in the mood for, in character. decision must be \"stay\".)"

local CUSTOMER_SCHEMA = [[Every reply must be ONLY a JSON object, no prose around it:
{"say": "what you say out loud (1-2 short sentences)",
 "decision": "stay" | "buy" | "leave",
 "items": {"menu_key": quantity, ...},
 "pay": total dollars you hand over,
 "stars": 1-5}
- "stay": keep talking. items/pay/stars are ignored.
- "buy": you take exactly "items" and pay "pay", then you leave. "say" is your goodbye line.
  "items" must list EVERY item you take, with the exact menu keys (e.g. {"hotchoc": 1, "cookie": 1}).
  "pay" is the total you agreed on (a discount the shopkeeper offered counts).
- "leave": you walk away without buying. "say" is your goodbye line.
- "stars" (on buy or leave): how you'd rate this shopkeeper to a friend. 5 = felt understood and well treated, 3 = fine, 1 = pushed, tricked or ignored.]]

local function customerSystem(pack: Pack, profile: CustomerProfile, repliesLeft: number): string
	local lastCall = ""
	if repliesLeft <= 0 then
		lastCall = "This is your LAST reply: decision MUST be \"buy\" or \"leave\" now."
	else
		lastCall = string.format(
			"You will listen to the shopkeeper for at most %d more replies before you decide. You may buy earlier if you're happy.",
			repliesLeft
		)
	end
	return table.concat({
		pack.cast.customerBase,
		string.format("You are %s, a %s customer. Right now you are %s.", profile.name, profile.ageGroup, profile.situation),
		"What actually tempts you (keep it private unless asked about what you like): " .. profile.taste .. ".",
		"How you feel about money and selling: " .. profile.sensitivity.prompt,
		string.format(
			"You have exactly $%d in your wallet. This is private: don't announce it, but you may hint ('I don't have much on me') or tell if asked kindly. You can NEVER spend more than $%d.",
			profile.wallet,
			profile.wallet
		),
		"Menu: " .. menuText(pack) .. ".",
		"Prices: you never pay MORE than the menu price for what you take. You may accept a fair discount the shopkeeper offers. If they try to overcharge, lie, or keep pushing after you said no, you get annoyed and may leave with low stars.",
		"You are persuadable by good selling: if the shopkeeper asks what you need and suggests something that really fits your situation and taste, you are happy to buy it (and maybe one more thing), as long as it fits your wallet.",
		lastCall,
		CUSTOMER_SCHEMA,
	}, "\n\n")
end

local function parseCustomer(raw: string): CustomerTurn
	local data = decodeObject(raw)
	if not data then
		-- the model answered in plain text: treat it as a line of dialogue
		local text = raw:gsub("^%s+", ""):gsub("%s+$", "")
		return { say = clip(text, 280), decision = "stay", items = {}, pay = 0, stars = 3 }
	end
	local items: { [string]: number } = {}
	if typeof(data.items) == "table" then
		for key, qty in data.items do
			local n = tonumber(qty)
			if typeof(key) == "string" and n and n > 0 then
				items[key] = math.floor(n)
			end
		end
	end
	local decision = typeof(data.decision) == "string" and string.lower(data.decision) or "stay"
	if decision ~= "buy" and decision ~= "leave" then
		decision = "stay"
	end
	return {
		say = clip(typeof(data.say) == "string" and data.say or "...", 280),
		decision = decision,
		items = items,
		pay = tonumber(data.pay) or -1, -- -1 = "menu price"
		stars = math.clamp(math.floor(tonumber(data.stars) or 3), 1, 5),
	}
end

-- `history` holds prior turns: user = shopkeeper lines, assistant = the
-- customer's raw JSON replies. Pass an empty history for the opening line.
function AgentRuntime.customerTurn(
	pack: Pack,
	profile: CustomerProfile,
	history: { LlmClient.ChatMessage },
	repliesLeft: number
): (boolean, CustomerTurn, string)
	local messages: { LlmClient.ChatMessage } = {
		{ role = "system", content = customerSystem(pack, profile, repliesLeft) },
	}
	if #history == 0 then
		table.insert(messages, { role = "user", content = AgentRuntime.OPENING_PROMPT })
	else
		for _, msg in history do
			table.insert(messages, msg)
		end
	end

	local ok, reply = LlmClient.chat(messages, {
		maxTokens = Config.MAX_TOKENS_CUSTOMER,
		temperature = 0.8,
		jsonMode = true,
	})
	if ok then
		local turn = parseCustomer(reply)
		if #history == 0 then
			turn.decision = "stay"
		end
		return true, turn, reply
	end
	-- model unreachable: keep the scene alive, let patience run out naturally
	local fallback: CustomerTurn = {
		say = if #history == 0 then "Hi! Hmm, what's good here today?" else "Hmm, let me think about that...",
		decision = if repliesLeft <= 0 then "leave" else "stay",
		items = {},
		pay = 0,
		stars = 3,
	}
	return false, fallback, HttpService:JSONEncode(fallback)
end

-- ========== Coach ==========

function AgentRuntime.coachHint(pack: Pack, profile: CustomerProfile, transcript: { string }): string
	local system = table.concat({
		pack.cast.coach,
		string.format("Customer the kid can see: %s, a %s, %s.", profile.name, profile.ageGroup, profile.situation),
		"Menu: " .. menuText(pack) .. ".",
		"Conversation so far:\n" .. (if #transcript > 0 then table.concat(transcript, "\n") else "(nothing yet)"),
	}, "\n\n")

	local ok, reply = LlmClient.chat({
		{ role = "system", content = system },
		{ role = "user", content = "Give me one short hint." },
	}, { maxTokens = 90, temperature = 0.6 })

	if ok then
		return clip(reply, 220)
	end
	return "Ask them one question about what they need right now, then suggest something that fits."
end

-- ========== Evaluator ==========

local EVAL_SCHEMA = [[Reply with ONLY a JSON object, no prose, no markdown fences, exactly this shape:
{
  "skills": [{"tag": "skill_tag", "name": "Plain-English skill name", "evidence": "one sentence citing a real customer and what the player did"}],
  "wentWell": ["short bullet", "..."],
  "wentWrong": ["short bullet", "..."],
  "realWorldTransfer": "one sentence: where the child will use this in their own life",
  "nextDrill": "one concrete thing to try next round"
}]]

local function toStringList(value: any): { string }
	if typeof(value) ~= "table" then
		return {}
	end
	local list = {}
	for _, item in value do
		if typeof(item) == "string" then
			table.insert(list, item)
		end
	end
	return list
end

local function tryParseEvaluation(raw: string): Evaluation?
	local data = decodeObject(raw)
	if not data then
		return nil
	end
	if typeof(data.skills) ~= "table" or typeof(data.realWorldTransfer) ~= "string" or typeof(data.nextDrill) ~= "string" then
		return nil
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
	return {
		skills = skills,
		wentWell = toStringList(data.wentWell),
		wentWrong = toStringList(data.wentWrong),
		realWorldTransfer = data.realWorldTransfer,
		nextDrill = data.nextDrill,
	}
end

local function fallbackEvaluation(records: { SaleRecord }): Evaluation
	local wentWell, wentWrong = {}, {}
	for _, r in records do
		if r.outcome == "bought" and r.stars >= 4 then
			table.insert(wentWell, string.format("%s paid $%d and left happy (%d stars).", r.customer, r.paid, r.stars))
		elseif r.stars <= 2 then
			table.insert(wentWrong, string.format("%s left with %d stars.", r.customer, r.stars))
		end
	end
	return {
		skills = {
			{ tag = "customer_service", name = "Serving customers", evidence = string.format("You talked with %d customers this round.", #records) },
		},
		wentWell = wentWell,
		wentWrong = wentWrong,
		realWorldTransfer = "Next time you sell something at a school fair or trade with a friend, ask what they need before you suggest anything.",
		nextDrill = "Ask every customer one question about what they need before you suggest an item.",
	}
end

function AgentRuntime.evaluate(pack: Pack, records: { SaleRecord }, summary: { [string]: any }): Evaluation
	if #records == 0 then
		return {
			skills = {},
			wentWell = {},
			wentWrong = { "No customer finished a conversation this round." },
			realWorldTransfer = "Selling starts with saying hello and asking what someone needs.",
			nextDrill = "Greet the very first customer and ask what they're in the mood for.",
		}
	end

	local system = table.concat({
		pack.cast.evaluator,
		"Skill tags available for this scenario: " .. table.concat(pack.skillTags, ", "),
		pack.debriefTemplate,
		EVAL_SCHEMA,
	}, "\n\n")

	local payload = HttpService:JSONEncode({
		scenario = pack.title,
		summary = summary,
		customers = records,
	})

	local messages: { LlmClient.ChatMessage } = {
		{ role = "system", content = system },
		{ role = "user", content = "Here is the full round record. Evaluate it.\n" .. payload },
	}

	for attempt = 1, 2 do
		local ok, reply = LlmClient.chat(messages, {
			maxTokens = Config.MAX_TOKENS_EVALUATION,
			temperature = 0.3,
			jsonMode = true,
		})
		if not ok then
			break
		end
		local parsed = tryParseEvaluation(reply)
		if parsed then
			return parsed
		end
		table.insert(messages, { role = "assistant", content = reply })
		table.insert(messages, { role = "user", content = "That was not valid JSON. Reply again with ONLY the JSON object." })
		if attempt == 1 then
			task.wait(0.5)
		end
	end

	warn("[KidSim] Evaluator fell back to deterministic debrief")
	return fallbackEvaluation(records)
end

return AgentRuntime
