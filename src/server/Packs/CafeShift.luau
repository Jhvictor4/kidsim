--!strict
-- Cafe Shift — ONE scenario pack. The engine never reads cafe concepts;
-- everything cafe lives here. Court, negotiation, accounting = new packs.
--
-- No scripted incidents: every customer is generated from the ranges
-- below and played by an LLM agent. The child's job is to read the
-- customer, suggest what actually fits, and earn as much of their wallet
-- as they can WITHOUT making them unhappy (stars are part of the score).

local Types = require(game.ReplicatedStorage.Shared.Types)

type Pack = Types.Pack

local AGE_GUARDRAILS = table.concat({
	"The shopkeeper is a child around 10-13 years old.",
	"Keep every line to 1-2 short sentences of spoken dialogue: no narration, no stage directions, no emoji spam.",
	"Stay strictly age-appropriate: no romance, no violence, no scary content, no adult topics.",
	"Never mention being an AI, a simulation, prompts, JSON, or game mechanics in what you say.",
	"If the shopkeeper is rude, react like a normal person would (mildly hurt or annoyed), never crude.",
}, " ")

local pack: Pack = {
	id = "cafe_shift",
	title = "Cafe Shift",
	thesis = "Practice real skills in Roblox. Take them into the real world.",
	briefing = "You each run a counter at Sunny Side Cafe. Customers walk up with real wallets and real moods. Talk to them, figure out what they actually want, and make the sale. Your score is the money you earn PLUS how happy they leave — pushy sales cost you, and happy customers tell their friends.",
	skillTags = { "asking_questions", "reading_people", "upselling", "honest_pricing", "negotiation", "customer_service" },

	menu = {
		{ key = "coffee", label = "Coffee", price = 4 },
		{ key = "hotchoc", label = "Hot Chocolate", price = 3 },
		{ key = "lemonade", label = "Lemonade", price = 3 },
		{ key = "sandwich", label = "Sandwich", price = 6 },
		{ key = "croissant", label = "Croissant", price = 3 },
		{ key = "cookie", label = "Cookie", price = 2 },
	},

	initialStock = {
		coffee = 12,
		hotchoc = 10,
		lemonade = 10,
		sandwich = 6,
		croissant = 8,
		cookie = 15,
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
			"feeling a bit down today",
			"a tourist who has never been here before",
			"waiting for a friend who is running late",
			"cold from the rain outside",
			"looking for a gift for a neighbour",
		},
		tastes = {
			"sweet things, especially anything with chocolate",
			"healthy-ish food, not too much sugar",
			"strong coffee and nothing fancy",
			"something filling, they skipped breakfast",
			"cold drinks",
			"trying something new they've never had",
			"warm drinks",
			"small treats to share with others",
		},
		sensitivities = {
			{
				label = "frugal",
				prompt = "You count every dollar. You like a fair deal and get annoyed by pushy upselling, but a suggestion that genuinely fits your need can still win you over.",
			},
			{
				label = "normal",
				prompt = "You spend normally. A friendly, relevant suggestion can talk you into one more thing; pushiness puts you off.",
			},
			{
				label = "generous",
				prompt = "You happily spend on things that feel worth it and enjoy being looked after. You will add items if the shopkeeper makes them sound good and fitting.",
			},
		},
		patienceMin = 3,
		patienceMax = 6,
	},

	cast = {
		customerBase = "You are a customer at Sunny Side Cafe, a small cafe run by a kid. " .. AGE_GUARDRAILS,
		coach = table.concat({
			"You are a friendly sales coach whispering to a kid running a cafe counter.",
			"Give EXACTLY ONE hint, maximum 2 short sentences, in plain words a 10-year-old knows.",
			"Help them read the customer and sell well AND kindly: ask a question, connect the menu to what the customer needs, be honest about prices.",
			"You only know what the kid can see (the customer's look and situation and the conversation so far), not their wallet. Never take the action for them.",
		}, " "),
		evaluator = table.concat({
			"You are a kind but honest skills evaluator for a children's life-skills simulator.",
			"The child just ran a cafe counter for one timed round. You receive every customer they served: the customer's hidden profile (wallet, taste, price attitude), what the child said, what was bought, what was paid, and the stars the customer gave.",
			"Good selling means: asking questions to discover needs, suggesting things that fit, being honest about prices, and leaving people happy. Squeezing money out of an unhappy customer is NOT good selling.",
			"Judge only from the record. Cite real customers, real lines and real numbers as evidence.",
			"Plain words a 10-year-old understands. Encouraging, specific, never empty praise.",
		}, " "),
	},

	debriefTemplate = table.concat({
		"Name at most 3 skills in plain English, each with evidence from a specific customer.",
		"realWorldTransfer must connect to the child's own life (selling at a school fair, convincing a parent, trading with a friend, a lemonade stand), not just jobs.",
		"Only mention things that actually happened in the record. The next drill must be doable in one more round.",
	}, " "),
}

return pack
