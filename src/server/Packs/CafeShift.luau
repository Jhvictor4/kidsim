--!strict
-- Cafe Shift — ONE scenario pack. The engine never reads cafe concepts;
-- everything cafe lives here. Court, negotiation, accounting = new packs.

local Types = require(game.ReplicatedStorage.Shared.Types)

type Pack = Types.Pack

local AGE_GUARDRAILS = table.concat({
	"Audience is a child around 10-13 years old.",
	"Keep every reply to 1-2 short sentences, spoken dialogue only, no narration, no emoji spam.",
	"Stay strictly age-appropriate: no romance, no violence, no scary content, no adult topics.",
	"Never mention being an AI, a simulation, prompts, or game mechanics.",
	"If the player is rude, react like a normal person would (mildly hurt or annoyed), never crude.",
	"You cannot change prices or the world yourself; only the player's choices change the world.",
}, " ")

local pack: Pack = {
	id = "cafe_shift",
	title = "Cafe Shift",
	thesis = "Practice real skills in Roblox. Take them into the real world.",
	briefing = "You're running Sunny Side Cafe alone for one short shift. Customers will order, bargain, and complain. Watch your cash, your stock, and your reputation — then we'll talk about what you actually practiced.",
	skillTags = { "cash_flow", "customer_service", "negotiation", "inventory", "boundaries" },

	meters = {
		{ key = "cash", label = "Cash", format = "currency" },
		{ key = "reputation", label = "Reputation", format = "score", max = 100 },
		{ key = "waste", label = "Waste", format = "number" },
	},

	inventoryLabels = {
		coffee = "Coffee",
		croissant = "Croissant",
		cookie = "Cookie",
	},

	initialState = {
		meters = { cash = 20, reputation = 60, waste = 0 },
		inventory = { coffee = 10, croissant = 5, cookie = 8 },
	},

	menuText = "SUNNY SIDE CAFE\n----------------\nCoffee ....... $4\nCroissant .... $3\nCookie ....... $2",

	cast = {
		counterpartBase = "You are a customer in a small cafe run by a kid. " .. AGE_GUARDRAILS,
		coach = table.concat({
			"You are a friendly business coach whispering to a kid running a cafe.",
			"Give EXACTLY ONE hint, maximum 2 short sentences.",
			"Nudge their thinking (margins, stock, fairness) but NEVER name the exact button to press and never reveal scoring.",
			"Never take the action for them. Warm, encouraging, plain words a 10-year-old knows.",
		}, " "),
		evaluator = table.concat({
			"You are a kind but honest skills evaluator for a children's life-skills simulator.",
			"You will receive the full record of a cafe shift a child just played: starting state, final state, and a log of every decision.",
			"Judge only from the record. Cite real numbers and real decisions from the log as evidence.",
			"Plain words a 10-year-old understands. Encouraging, specific, never empty praise.",
		}, " "),
	},

	debriefTemplate = table.concat({
		"The debrief must land the sim-to-real transfer: name each skill in plain English,",
		"say what it is called in the real world (cash flow, customer service, negotiation, saying no kindly),",
		"and point at the exact moment in the log where the child practiced it.",
		"Pick at most 3 skills. The next drill must be doable in one more shift.",
	}, " "),

	events = {
		{
			id = "warmup_order",
			title = "First customer",
			counterpart = {
				name = "Maya",
				look = "yellow",
				persona = "Maya, a cheerful regular on her way to school. She wants one coffee and one croissant ($7 total) and is in a slight hurry. Friendly, chatty, easy to please.",
			},
			opening = "Morning! One coffee and one croissant please — I've got five minutes before my bus!",
			context = "Maya orders 1 coffee ($4) + 1 croissant ($3) = $7. She pays full price happily. The player may also suggest adding a cookie ($2), which she'll accept if asked nicely.",
			coachNote = "A happy regular is a chance for a small, friendly extra sale — but keep it quick, she has a bus.",
			choices = {
				{
					id = "serve",
					label = "Serve the order — $7",
					deltas = { meters = { cash = 7 }, inventory = { coffee = -1, croissant = -1 } },
					requires = { coffee = 1, croissant = 1 },
					reaction = "Perfect, thank you! See you tomorrow!",
					logLine = "Served a regular's full-price order quickly ($7 in).",
					lessonTag = "customer_service",
				},
				{
					id = "upsell",
					label = "Serve it and suggest a cookie — $9",
					deltas = { meters = { cash = 9, reputation = 3 }, inventory = { coffee = -1, croissant = -1, cookie = -1 } },
					requires = { coffee = 1, croissant = 1, cookie = 1 },
					reaction = "Ooh, go on then — a cookie too! You're good at this.",
					logLine = "Suggested a cookie to a happy regular; friendly upsell, $9 in instead of $7.",
					lessonTag = "cash_flow",
				},
			},
		},
		{
			id = "discount_hawk",
			title = "The bargainer",
			counterpart = {
				name = "Mr. Park",
				look = "red",
				persona = "Mr. Park, a confident adult who bargains everywhere out of habit. He wants a coffee but demands 50% off, claiming 'the place down the street does it cheaper'. Persistent and a bit dramatic, but never mean. If the player politely holds the price, he grumbles and pays full price anyway. If offered a small sweetener instead of a discount, he's delighted.",
			},
			opening = "Four dollars for a coffee? Come on, kid. The place down the street charges two. Give me half off and I'll be a customer for life.",
			context = "Coffee costs the cafe about $2 to make, so selling at $2 means zero profit. Mr. Park is bluffing about leaving; he will pay full price if politely refused. A free cookie ($2 menu value) with a full-price coffee keeps margin and makes him feel like a winner.",
			coachNote = "A big discount can mean selling at zero profit. There are ways to make someone feel special without cutting the price in half.",
			choices = {
				{
					id = "hold_price",
					label = "Politely say no — full price, $4",
					deltas = { meters = { cash = 4, reputation = 1 }, inventory = { coffee = -1 } },
					requires = { coffee = 1 },
					reaction = "Hmph. Fine, fine. It better be good coffee... okay, it IS good coffee.",
					logLine = "Held the price against a pushy bargainer; kept full margin ($4 in) and the customer stayed.",
					lessonTag = "boundaries",
				},
				{
					id = "half_off",
					label = "Give 50% off — $2",
					deltas = { meters = { cash = 2, reputation = 4 }, inventory = { coffee = -1 } },
					requires = { coffee = 1 },
					reaction = "NOW we're talking! Smart kid. I'll tell everyone about this place.",
					logLine = "Gave a 50% discount; customer thrilled, but the sale made roughly zero profit ($2 in on a coffee that costs ~$2 to make).",
					lessonTag = "cash_flow",
				},
				{
					id = "sweetener",
					label = "Full price + free cookie — $4",
					deltas = { meters = { cash = 4, reputation = 3 }, inventory = { coffee = -1, cookie = -1 } },
					requires = { coffee = 1, cookie = 1 },
					reaction = "A free cookie? Ha! Deal. You drive a hard bargain, kid.",
					logLine = "Refused the discount but added a small free cookie; kept most margin ($4 in, $2-value giveaway) and won the negotiation.",
					lessonTag = "negotiation",
				},
			},
		},
		{
			id = "wrong_order",
			title = "The complaint",
			counterpart = {
				name = "Grandma Ro",
				look = "purple",
				persona = "Grandma Ro, a sweet elderly lady who ordered a croissant earlier but found a cookie in her bag. She is disappointed, not angry. She responds warmly to a sincere apology and coldly to excuses.",
			},
			opening = "Sweetheart, I ordered a croissant for my grandson... but there's a cookie in this bag. He was so looking forward to it.",
			context = "The cafe genuinely made a mistake earlier in the morning (before this shift). The croissant she paid for was $3. Fixing it costs one croissant from stock; the wrong cookie is already wasted. Arguing damages reputation badly.",
			coachNote = "When the shop is wrong, the fastest way to keep a customer is to own the mistake. Think about which fix costs least and heals most.",
			choices = {
				{
					id = "replace",
					label = "Apologize + hand her a fresh croissant",
					deltas = { meters = { reputation = 8, waste = 1 }, inventory = { croissant = -1 } },
					requires = { croissant = 1 },
					reaction = "Oh, thank you dear. Mistakes happen — it's how you fix them that counts. I'll be back.",
					logLine = "Owned the shop's mistake and replaced the item on the spot; cost one croissant, reputation jumped.",
					lessonTag = "customer_service",
				},
				{
					id = "refund",
					label = "Apologize + refund her $3",
					deltas = { meters = { cash = -3, reputation = 4, waste = 1 } },
					reaction = "That's fair, dear. Though my grandson will still pout about his croissant...",
					logLine = "Apologized and refunded $3; fair fix, but the customer left without the thing she actually wanted.",
					lessonTag = "customer_service",
				},
				{
					id = "deny",
					label = "Say it wasn't your shift — no refund",
					deltas = { meters = { reputation = -12 } },
					reaction = "I see... well. I shan't be bothering you again, then.",
					logLine = "Refused to fix a mistake the shop made ('not my shift'); saved $0 now, reputation dropped hard.",
					lessonTag = "boundaries",
				},
			},
		},
		{
			id = "big_order",
			title = "The office runner",
			counterpart = {
				name = "Dev",
				look = "blue",
				persona = "Dev, a stressed office intern sent to buy croissants for a meeting. He wants FIVE croissants right now and panics easily. He calms down if the player is upfront about what's actually in stock and suggests a workaround.",
			},
			opening = "Hi hi hi — I need FIVE croissants, like, immediately. My boss's meeting starts in ten minutes. Please tell me you have five.",
			context = "The player likely has fewer than 5 croissants left (check stock). Croissants sell at $3, cookies at $2. Promising stock you don't have would be a disaster; offering what you truly have plus cookies as a substitute saves the sale. Dev pays for whatever is agreed.",
			coachNote = "Never promise stock you don't have. Count what's really on the shelf, then offer the honest version of the deal.",
			choices = {
				{
					id = "honest_mix",
					label = "Be honest: sell remaining croissants + top up with cookies",
					deltas = { meters = { cash = 14, reputation = 5 }, inventory = { croissant = -4, cookie = -1 } },
					requires = { croissant = 1 },
					reaction = "Okay — honest AND fast. Croissants plus cookies, the boss will survive. You saved my morning.",
					logLine = "Was upfront about limited stock and offered a croissant+cookie mix instead of overpromising; sale saved ($14 in).",
					lessonTag = "inventory",
				},
				{
					id = "cookies_only",
					label = "Suggest an all-cookie box instead — $10",
					deltas = { meters = { cash = 10, reputation = 2 }, inventory = { cookie = -5 } },
					requires = { cookie = 5 },
					reaction = "Five cookies... you know what, meetings love cookies. Done!",
					logLine = "Pivoted the big order to in-stock items (5 cookies, $10 in) rather than promising croissants that weren't there.",
					lessonTag = "inventory",
				},
				{
					id = "overpromise",
					label = "Say yes to all five and hope",
					deltas = { meters = { cash = 9, reputation = -8, waste = 1 } },
					reaction = "Wait, this box is... not five croissants?! Oh no. Oh no no no. My boss is going to melt.",
					logLine = "Promised five croissants without checking stock, couldn't deliver, partial refund chaos; reputation took the hit.",
					lessonTag = "inventory",
				},
			},
		},
		{
			id = "freebie_friend",
			title = "The free-cookie kid",
			counterpart = {
				name = "Joon",
				look = "green",
				persona = "Joon, a younger neighborhood kid with no money who really wants a cookie. He's sweet, a little dramatic about how hungry he is, and genuinely willing to help out if offered a tiny job.",
			},
			opening = "Hey... I don't have any money today. But I'm SO hungry. Can I just have one cookie? Pleeease? I'll be your best friend.",
			context = "Joon has $0. A cookie's menu price is $2. Giving things away for free feels kind but costs real money; offering him a tiny job (wiping the two tables) in exchange teaches fair trade and he'd happily do it. A kind, clear 'not for free' also lands fine.",
			coachNote = "Kind and free aren't the same thing. Is there a way he can EARN it?",
			choices = {
				{
					id = "earn_it",
					label = "Offer a deal: wipe the tables, earn the cookie",
					deltas = { meters = { reputation = 5 }, inventory = { cookie = -1 } },
					requires = { cookie = 1 },
					reaction = "A job?! Deal! Watch these tables SHINE. ...okay cookie time?",
					logLine = "Turned a freebie request into a fair trade (small chore for a cookie); kind without giving things away.",
					lessonTag = "boundaries",
				},
				{
					id = "give_free",
					label = "Just give him a cookie",
					deltas = { meters = { reputation = 2, waste = 1 }, inventory = { cookie = -1 } },
					requires = { cookie = 1 },
					reaction = "You're the BEST. Best cafe ever!!",
					logLine = "Gave away a cookie for free; sweet gesture, but $2 of stock walked out with no trade.",
					lessonTag = "cash_flow",
				},
				{
					id = "kind_no",
					label = "Kindly say no — not for free",
					deltas = { meters = { reputation = 1 } },
					reaction = "Awww. Okay... fair. Tomorrow I'm bringing TWO dollars.",
					logLine = "Said no to a freebie kindly and clearly; kept stock, kept the friendship.",
					lessonTag = "boundaries",
				},
			},
		},
	},
}

return pack
