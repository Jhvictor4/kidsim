--!strict
-- The personas: customer (decides what to buy and how happy it is), staff
-- (serves the customer under the owner's rules and its hidden personality,
-- and may walk over to ask the owner), evaluator (structured debrief JSON).
-- All prompt text comes from the pack — this module stays pack-agnostic.
-- Everything an agent "decides" is only a proposal: ShopEngine validates
-- it against menu, stock, wallet and the owner's rules.

local HttpService = game:GetService("HttpService")

local LlmClient = require(script.Parent.LlmClient)
local Config = require(script.Parent.Config)
local Types = require(game.ReplicatedStorage.Shared.Types)

type Pack = Types.Pack
type CustomerProfile = Types.CustomerProfile
type StaffProfile = Types.StaffProfile
type CustomerTurn = Types.CustomerTurn
type StaffTurn = Types.StaffTurn
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

local function trim(text: string): string
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- ========== Customer ==========

-- Stage direction that makes the customer speak first. ShopEngine seeds the
-- customer's history with it so later turns start with a user message.
AgentRuntime.OPENING_PROMPT =
	"(You just walked up to the counter. Greet the staff member and say roughly what you're in the mood for, in character. decision must be \"stay\".)"

local CUSTOMER_SCHEMA = [[Every reply must be ONLY a JSON object, no prose around it:
{"say": "what you say out loud (1-2 short sentences)",
 "decision": "stay" | "buy" | "leave",
 "items": {"menu_key": quantity, ...},
 "pay": total dollars you hand over,
 "stars": 1-5,
 "complaint": "only if stars <= 2: a few words on why"}
- "stay": keep talking. items/pay/stars are ignored.
- "buy": you take exactly "items" and pay "pay", then you leave. "say" is your goodbye line.
  "items" must list EVERY item you take, with the exact menu keys (e.g. {"hotchoc": 1, "cookie": 1}).
  "pay" is the total you agreed on (a discount the staff member gave counts).
- "leave": you walk away without buying. "say" is your goodbye line.
- "stars" (on buy or leave): how you'd rate this cafe's service to a friend. 5 = felt understood and well treated, 3 = fine, 1 = pushed, tricked, rushed or treated rudely.]]

local function customerSystem(pack: Pack, profile: CustomerProfile, repliesLeft: number): string
	local lastCall = if repliesLeft <= 0
		then "This is your LAST reply: decision MUST be \"buy\" or \"leave\" now."
		else string.format(
			"You will listen to the staff member for at most %d more replies before you decide. You may buy earlier if you're happy.",
			repliesLeft
		)
	return table.concat({
		pack.cast.customerBase,
		string.format("You are %s, a %s customer. Right now you are %s.", profile.name, profile.ageGroup, profile.situation),
		"What actually tempts you (keep it private unless asked): " .. profile.taste .. ".",
		"How you feel about money and selling: " .. profile.sensitivity.prompt,
		string.format(
			"You have exactly $%d in your wallet. This is private: don't announce it, but you may hint or tell if asked kindly. You can NEVER spend more than $%d.",
			profile.wallet,
			profile.wallet
		),
		"Menu: " .. menuText(pack) .. ".",
		"You never pay MORE than the menu price. You may accept a discount the staff member offers. If they are pushy, rude, dishonest or keep pushing after you said no, you get annoyed and give low stars.",
		"Good service (asking what you need, suggesting something that fits, being kind) makes you happy to buy.",
		lastCall,
		CUSTOMER_SCHEMA,
	}, "\n\n")
end

local function parseCustomer(raw: string): CustomerTurn
	local data = decodeObject(raw)
	if not data then
		return { say = clip(trim(raw), 280), decision = "stay", items = {}, pay = 0, stars = 3 }
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
		complaint = if typeof(data.complaint) == "string" and #data.complaint > 0 then clip(data.complaint, 80) else nil,
	}
end

-- `history`: user = staff lines, assistant = the customer's raw JSON replies.
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
	local fallback: CustomerTurn = {
		say = if #history == 0 then "Hi! Hmm, what's good here today?" else "Hmm, let me think about that...",
		decision = if repliesLeft <= 0 then "leave" else "stay",
		items = {},
		pay = 0,
		stars = 3,
	}
	return false, fallback, HttpService:JSONEncode(fallback)
end

-- ========== Staff ==========

local STAFF_SCHEMA = [[Every reply must be ONLY a JSON object, no prose around it:
{"say": "what you say to the customer now (1-2 short sentences)",
 "action": "talk" | "ask_owner",
 "question": "only for ask_owner: short question for the owner",
 "options": ["only for ask_owner: 2-3 short answers the owner can pick"]}
- "talk": you just say "say" to the customer.
- "ask_owner": "say" is what you tell the customer before walking over (e.g. "Let me check with my boss!"); then you walk to the owner's throne and wait for an answer.]]

export type StaffContext = {
	rules: { string }, -- the owner's current rules, as instructions
	feedback: { string }, -- praise / warnings from the owner so far
	customer: CustomerProfile,
	alreadyAsked: boolean,
}

local function staffSystem(pack: Pack, staff: StaffProfile, ctx: StaffContext): string
	local parts = {
		pack.cast.staffBase,
		string.format("You are %s. Your real personality (stay true to it, even when it breaks the rules): %s", staff.name, staff.personality.prompt),
		"The owner's house rules right now:\n- " .. table.concat(ctx.rules, "\n- "),
	}
	if #ctx.feedback > 0 then
		table.insert(parts, "What the owner has told you about your work:\n- " .. table.concat(ctx.feedback, "\n- "))
	end
	table.insert(parts, "Menu: " .. menuText(pack) .. ". You cannot see the customer's wallet.")
	table.insert(parts, string.format(
		"The customer in front of you: %s, a %s customer, %s.",
		ctx.customer.name,
		ctx.customer.ageGroup,
		ctx.customer.situation
	))
	if ctx.alreadyAsked then
		table.insert(parts, "You already asked the owner during this visit. Do not ask again; use \"talk\".")
	else
		table.insert(parts, "Only use \"ask_owner\" when the rules say to ask, or when you are truly unsure.")
	end
	table.insert(parts, STAFF_SCHEMA)
	return table.concat(parts, "\n\n")
end

local function parseStaff(raw: string): StaffTurn
	local data = decodeObject(raw)
	if not data then
		return { say = clip(trim(raw), 280), action = "talk", options = {} }
	end
	local options = {}
	if typeof(data.options) == "table" then
		for _, opt in data.options do
			if typeof(opt) == "string" and #opt > 0 and #options < 3 then
				table.insert(options, clip(opt, 60))
			end
		end
	end
	local action = if typeof(data.action) == "string" and string.lower(data.action) == "ask_owner" then "ask_owner" else "talk"
	local question = if typeof(data.question) == "string" and #data.question > 0 then clip(data.question, 160) else nil
	if action == "ask_owner" and (question == nil or #options < 2) then
		action = "talk" -- a question without choices can't be answered by a button
	end
	return {
		say = clip(typeof(data.say) == "string" and data.say or "...", 280),
		action = action,
		question = question,
		options = options,
	}
end

-- `history`: user = customer lines / owner answers, assistant = the staff's raw JSON.
function AgentRuntime.staffTurn(
	pack: Pack,
	staff: StaffProfile,
	ctx: StaffContext,
	history: { LlmClient.ChatMessage }
): (boolean, StaffTurn, string)
	local messages: { LlmClient.ChatMessage } = {
		{ role = "system", content = staffSystem(pack, staff, ctx) },
	}
	for _, msg in history do
		table.insert(messages, msg)
	end
	local ok, reply = LlmClient.chat(messages, {
		maxTokens = Config.MAX_TOKENS_STAFF,
		temperature = 0.8,
		jsonMode = true,
	})
	if ok then
		local turn = parseStaff(reply)
		if ctx.alreadyAsked then
			turn.action = "talk"
		end
		return true, turn, reply
	end
	local fallback: StaffTurn = { say = "What can I get you today?", action = "talk", options = {} }
	return false, fallback, HttpService:JSONEncode(fallback)
end

-- ========== Evaluator ==========

local EVAL_SCHEMA = [[Reply with ONLY a JSON object, no prose, no markdown fences, exactly this shape:
{
  "skills": [{"tag": "skill_tag", "name": "Plain-English skill name", "evidence": "one sentence citing a real moment"}],
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

local function fallbackEvaluation(record: { [string]: any }): Evaluation
	local wentWell, wentWrong = {}, {}
	for _, s in (record.staff or {}) do
		if s.ruleBreaks > 0 and not s.fired then
			table.insert(wentWrong, string.format("%s broke your rules %d times and kept working.", s.name, s.ruleBreaks))
		elseif s.ruleBreaks > 0 and s.fired then
			table.insert(wentWell, string.format("You noticed %s breaking the rules and acted.", s.name))
		end
	end
	return {
		skills = {
			{ tag = "setting_clear_rules", name = "Running a team", evidence = "You set the house rules and watched your staff work." },
		},
		wentWell = wentWell,
		wentWrong = wentWrong,
		realWorldTransfer = "Next time you lead a group project, agree on the rules first and check who actually follows them.",
		nextDrill = "Answer every staff question within a few seconds next round.",
	}
end

function AgentRuntime.evaluate(pack: Pack, record: { [string]: any }): Evaluation
	local system = table.concat({
		pack.cast.evaluator,
		"Skill tags available for this scenario: " .. table.concat(pack.skillTags, ", "),
		pack.debriefTemplate,
		EVAL_SCHEMA,
	}, "\n\n")

	local messages: { LlmClient.ChatMessage } = {
		{ role = "system", content = system },
		{ role = "user", content = "Here is the full round record. Evaluate it.\n" .. HttpService:JSONEncode(record) },
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
	return fallbackEvaluation(record)
end

return AgentRuntime
