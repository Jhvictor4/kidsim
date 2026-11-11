--!strict
-- Cafe Shift — ONE scenario pack. The engine never reads cafe concepts;
-- everything cafe lives here. Court, negotiation, accounting = new packs.
--
-- The child is the OWNER. Three staff agents (each with a hidden
-- personality) serve random customer agents. The owner sets the rules,
-- answers staff who walk over with questions, and praises, warns or fires
-- staff based on what they see. Score = money + happy customers.

local Types = require(game.ReplicatedStorage.Shared.Types)

type Pack = Types.Pack

local AGE_GUARDRAILS = table.concat({
	"Everything happens in a cafe owned by a child around 10-13 years old.",
	"Keep every line to 1-2 short sentences of spoken dialogue: no narration, no stage directions, no emoji spam.",
	"Stay strictly age-appropriate: no romance, no violence, no scary content, no adult topics, no swearing.",
	"Never mention being an AI, a simulation, prompts, JSON, or game mechanics in what you say.",
}, " ")

local pack: Pack = {
	id = "cafe_shift",
	title = "Cafe Shift",
	thesis = "Practice real skills in Roblox. Take them into the real world.",
	briefing = "You OWN Sunny Side Cafe. Three staff run your counters — but each one has a hidden personality. Set the house rules, answer staff who come to your throne with questions, and keep an eye on who breaks the rules. Praise good work, warn, or fire. Your score is money earned plus happy customers.",
	skillTags = { "setting_clear_rules", "delegating", "judging_from_evidence", "giving_feedback", "fair_decisions", "responding_to_your_team" },

	menu = {
		{ key = "coffee", label = "Coffee", price = 4 },
		{ key = "hotchoc", label = "Hot Chocolate", price = 3 },
		{ key = "lemonade", label = "Lemonade", price = 3 },
		{ key = "sandwich", label = "Sandwich", price = 6 },
		{ key = "croissant", label = "Croissant", price = 3 },
		{ key = "cookie", label = "Cookie", price = 2 },
	},

	initialStock = {
		coffee = 20,
		hotchoc = 16,
		lemonade = 16,
		sandwich = 10,
		croissant = 14,
		cookie = 24,
	},

	customers = {
		names = {
			"Maya", "Mr. Park", "Grandma Ro", "Dev", "Joon", "Aisha", "Leo", "Ms. Okafor", "Sam", "Yuna",
			"Carlos", "Priya", "Ben", "Hana", "Mr. Silva", "Zoe", "Omar", "Lily", "Grandpa Ken", "Nina",
		},
		looks = { "yellow", "red", "purple", "blue", "green", "orange", "pink", "teal" },
		ageGroups = {
			{ label = "kid", budgetMin = 2, budgetMax = 8, weight = 2 },
			{ label = "teen", budgetMin = 5, budgetMax = 14, weight = 3 },
			{ label = "adult", budgetMin = 8, budgetMax = 30, weight = 4 },
			{ label = "senior", budgetMin = 6, budgetMax = 20, weight = 2 },
		},
		situations = {
			"in a hurry to catch the bus",
			"on a lunch break from work",
			"treating a grandchild to something nice",
			"studying for a big test later today",
			"picking up snacks for a team meeting",
			"just finished soccer practice and is starving",
			"celebrating a friend's birthday",
			"a tourist who has never been here before",
			"cold from the rain outside",
			"a regular who always asks for a deal",
		},
		tastes = {
			"sweet things, especially anything with chocolate",
			"healthy-ish food, not too much sugar",
			"strong coffee and nothing fancy",
			"something filling, they skipped breakfast",
			"cold drinks",
			"trying something new they've never had",
			"small treats to share with others",
		},
		sensitivities = {
			{
				label = "bargain-hunter",
				pressure = true,
				prompt = "You always ask for a discount first (try for 30-50% off) and push a bit. You still pay full price if the staff member politely holds firm and the offer fits your need.",
			},
			{
				label = "normal",
				prompt = "You spend normally. A friendly, relevant suggestion can talk you into one more thing; pushiness or rudeness puts you off.",
			},
			{
				label = "generous",
				prompt = "You happily spend on things that feel worth it and enjoy being looked after.",
			},
		},
		patienceMin = 2,
		patienceMax = 4,
	},

	staff = {
		names = { "Mina", "Jake", "Sora", "Theo", "Ivy", "Max", "Ruby", "Kai", "Lena", "Finn" },
		looks = { "white", "brown", "navy", "olive" },
		personalities = {
			{
				label = "Star",
				weight = 2,
				prompt = "You are warm and professional. You ask customers what they need, suggest things that fit, follow the owner's rules exactly, and ask the owner when a request is outside the rules.",
			},
			{
				label = "Pushover",
				weight = 2,
				problem = true,
				prompt = "You hate saying no. When a customer asks for a discount you usually give it, often bigger than the owner allows, and you rarely bother asking the owner first.",
			},
			{
				label = "Pushy seller",
				weight = 2,
				problem = true,
				prompt = "You care only about selling more. You keep pushing extra items even after the customer says no, and you exaggerate how good things are.",
			},
			{
				label = "Grumpy",
				weight = 1,
				problem = true,
				prompt = "You are impatient and short with customers, especially ones who can't decide or ask for deals. You follow the price rules but you sound annoyed.",
			},
			{
				label = "Worrier",
				weight = 1,
				asksOften = true,
				prompt = "You are kind but unsure of yourself. You ask the owner about almost every small decision, even ones the rules already cover.",
			},
		},
	},

	policies = {
		{
			key = "discounts",
			title = "Discounts",
			default = 2,
			options = {
				{ label = "No discounts", prompt = "Never give a discount; always charge menu price.", maxDiscountPct = 0 },
				{ label = "Up to 10% off", prompt = "You may give at most 10% off, only if it saves the sale.", maxDiscountPct = 10 },
				{ label = "Staff decide", prompt = "You may decide discounts yourself; keep the cafe making money." },
			},
		},
		{
			key = "selling",
			title = "Selling",
			default = 2,
			options = {
				{ label = "Just take orders", prompt = "Only sell what the customer asks for. Don't suggest extras." },
				{ label = "Suggest one extra", prompt = "Ask what the customer needs and suggest at most one extra item that fits. Accept a no." },
				{ label = "Sell as much as you can", prompt = "Try hard to sell as many items as possible to every customer." },
			},
		},
		{
			key = "askMe",
			title = "Ask me first",
			default = 2,
			options = {
				{ label = "Never — decide yourself", prompt = "Don't come to the owner; make every decision yourself." },
				{ label = "Big discounts", prompt = "Ask the owner before giving more than 10% off.", askAboveDiscountPct = 10 },
				{ label = "Any discount or freebie", prompt = "Ask the owner before giving ANY discount or anything free.", askAboveDiscountPct = 0 },
			},
		},
	},

	cast = {
		customerBase = "You are a customer at Sunny Side Cafe, talking to a staff member at the counter. " .. AGE_GUARDRAILS,
		staffBase = "You work the counter at Sunny Side Cafe. Your boss is the cafe owner, a kid, who sits on a throne in the shop. " .. AGE_GUARDRAILS,
		evaluator = table.concat({
			"You are a kind but honest skills evaluator for a children's life-skills simulator.",
			"The child just played the OWNER of a cafe for one timed round. Staff agents with hidden personalities served customers; the child set house rules, answered staff questions, and praised, warned or fired staff.",
			"You receive the rules the child chose, every owner action with its time, every sale (staff, customer, discount, stars, rule breaks), and each staff member's hidden personality.",
			"Good owning means: clear rules, answering the team quickly, judging staff from evidence (rule breaks, unhappy customers), warning before firing when fair, and keeping customers happy.",
			"Judge only from the record. Cite real staff names, real moments and real numbers. Plain words a 10-year-old understands. Encouraging, specific, never empty praise.",
		}, " "),
	},

	debriefTemplate = table.concat({
		"Name at most 3 skills in plain English (e.g. setting clear rules, judging people by what they do, giving fair feedback), each with evidence from a real moment.",
		"In wentWell/wentWrong, say for each staff member whether the child read them correctly (their hidden personality is in the record).",
		"realWorldTransfer must connect to the child's own life (leading a group project, team captain, organising a class event, babysitting), not just jobs.",
		"Only mention things that actually happened. The next drill must be doable in one more round.",
	}, " "),
}

return pack
