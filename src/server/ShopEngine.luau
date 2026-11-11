--!strict
-- One owner's shop for one timed round. Three staff agents (hidden
-- personalities) each serve a stream of random customer agents at their
-- counter. The owner never talks to customers; they:
--   * set the house rules (policy chips; live, any time),
--   * answer staff who walk to the throne with a question (buttons),
--   * praise, warn or fire staff from the evidence they see.
-- The server validates every sale (menu price, stock, wallet), checks it
-- against the owner's rules, and keeps the record the evaluator reads.
--
-- Pack-agnostic: no cafe concepts in this file.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Types = require(game.ReplicatedStorage.Shared.Types)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local AgentRuntime = require(script.Parent.AgentRuntime)
local CustomerGen = require(script.Parent.CustomerGen)
local Config = require(script.Parent.Config)
local LlmClient = require(script.Parent.LlmClient)

type Pack = Types.Pack
type CustomerProfile = Types.CustomerProfile
type StaffProfile = Types.StaffProfile
type CustomerTurn = Types.CustomerTurn
type SaleRecord = Types.SaleRecord
type OwnerEvent = Types.OwnerEvent
type Voice = Types.Voice

export type CounterHooks = {
	spawnStaff: (StaffProfile) -> (),
	despawnStaff: () -> (),
	staffSay: (string?) -> (),
	staffWalkTo: (number?) -> (),
	staffPosition: () -> Vector3?,
	spawnCustomer: (CustomerProfile) -> (),
	despawnCustomer: () -> (),
	customerSay: (string?) -> (),
	customerPosition: () -> Vector3?,
}

export type ShopHooks = {
	counters: { CounterHooks },
	throne: Seat,
	setSign: (string, string) -> (),
	setOpen: (boolean) -> (),
}

export type ShopStats = {
	revenue: number,
	avgStars: number,
	served: number,
	score: number,
	hireFees: number,
	walletSeen: number,
}

-- Everything about one staff member's time at the shop (kept after firing).
type StaffRecord = {
	profile: StaffProfile,
	counter: number,
	status: string,
	sales: number,
	served: number,
	starsSum: number,
	ruleBreaks: number,
	issues: { string },
	feedback: { string },
	praised: number,
	warned: number,
	fired: boolean,
	firedAt: number?,
	hiredAt: number,
}

type Question = {
	id: number,
	counter: number,
	staff: string,
	question: string,
	options: { string },
	askedAt: number,
	answer: string?,
	done: boolean,
}

type Slot = {
	staff: StaffRecord?,
	fireRequested: boolean,
}

local ShopEngine = {}
ShopEngine.__index = ShopEngine

export type ShopEngineInstance = typeof(setmetatable(
	{} :: {
		pack: Pack,
		owner: Player,
		shop: ShopHooks,
		startedAt: number,
		endsAt: number,
		onChange: () -> (),
		rng: Random,
		stock: { [string]: number },
		revenue: number,
		starsSum: number,
		starsCount: number,
		walletSeen: number,
		hireFees: number,
		policy: { [string]: number },
		slots: { Slot },
		allStaff: { StaffRecord },
		sales: { SaleRecord },
		ownerEvents: { OwnerEvent },
		questions: { Question },
		nextQuestionId: number,
		_connections: { RBXScriptConnection },
		_running: boolean,
	},
	ShopEngine
))

local STAR_GLYPHS = { "★☆☆☆☆", "★★☆☆☆", "★★★☆☆", "★★★★☆", "★★★★★" }
local DECIDE_YOURSELF = "You decide"

function ShopEngine.new(pack: Pack, owner: Player, shop: ShopHooks, startedAt: number, endsAt: number, onChange: () -> ()): ShopEngineInstance
	local stock = {}
	for key, count in pack.initialStock do
		stock[key] = count
	end
	local policy = {}
	for _, p in pack.policies do
		policy[p.key] = p.default
	end
	local slots = {}
	for i = 1, #shop.counters do
		slots[i] = { staff = nil, fireRequested = false }
	end
	local self = setmetatable({
		pack = pack,
		owner = owner,
		shop = shop,
		startedAt = startedAt,
		endsAt = endsAt,
		onChange = onChange,
		rng = Random.new(),
		stock = stock,
		revenue = 0,
		starsSum = 0,
		starsCount = 0,
		walletSeen = 0,
		hireFees = 0,
		policy = policy,
		slots = slots,
		allStaff = {},
		sales = {},
		ownerEvents = {},
		questions = {},
		nextQuestionId = 0,
		_connections = {},
		_running = false,
	}, ShopEngine)
	return self :: ShopEngineInstance
end

-- ---------- time / liveness ----------

function ShopEngine.now(self: ShopEngineInstance): number
	return math.floor(os.clock() - self.startedAt + 0.5)
end

function ShopEngine.isLive(self: ShopEngineInstance): boolean
	return self._running and os.clock() < self.endsAt and self.owner.Parent == Players
end

function ShopEngine.logOwner(self: ShopEngineInstance, kind: string, staff: string?, detail: string)
	table.insert(self.ownerEvents, { t = self:now(), kind = kind, staff = staff, detail = detail })
end

-- ---------- stats ----------

function ShopEngine.stats(self: ShopEngineInstance): ShopStats
	local starBonus = self.starsSum - 3 * self.starsCount
	return {
		revenue = self.revenue,
		avgStars = if self.starsCount > 0 then self.starsSum / self.starsCount else 0,
		served = self.starsCount,
		score = self.revenue - self.hireFees + Config.STARS_WEIGHT * starBonus,
		hireFees = self.hireFees,
		walletSeen = self.walletSeen,
	}
end

function ShopEngine.buzz(self: ShopEngineInstance): number
	if self.starsCount == 0 then
		return 1
	end
	local avg = self.starsSum / self.starsCount
	return math.clamp(1 + Config.BUZZ_PER_STAR * (avg - 3), Config.BUZZ_MIN, Config.BUZZ_MAX)
end

function ShopEngine.policyOption(self: ShopEngineInstance, key: string)
	for _, p in self.pack.policies do
		if p.key == key then
			return p.options[self.policy[key] or p.default], p
		end
	end
	return nil, nil
end

function ShopEngine.rulePrompts(self: ShopEngineInstance): { string }
	local rules = {}
	for _, p in self.pack.policies do
		local option = p.options[self.policy[p.key] or p.default]
		table.insert(rules, p.title .. ": " .. option.prompt)
	end
	return rules
end

-- ---------- replication ----------

function ShopEngine.sendState(self: ShopEngineInstance)
	local stats = self:stats()
	local staffCards = {}
	for i, slot in self.slots do
		local rec = slot.staff
		if rec then
			table.insert(staffCards, {
				counter = i,
				name = rec.profile.name,
				look = rec.profile.look,
				status = rec.status,
				sales = rec.sales,
				served = rec.served,
				avgStars = if rec.served > 0 then rec.starsSum / rec.served else 0,
				ruleBreaks = rec.ruleBreaks,
				lastIssue = rec.issues[#rec.issues],
				warned = rec.warned,
				praised = rec.praised,
				leaving = slot.fireRequested,
			})
		else
			table.insert(staffCards, { counter = i, hiring = true })
		end
	end
	Remotes.get("State"):FireClient(self.owner, {
		revenue = stats.revenue,
		avgStars = stats.avgStars,
		served = stats.served,
		score = stats.score,
		hireFees = stats.hireFees,
		stock = self.stock,
		staff = staffCards,
		policy = self.policy,
	})
	self.shop.setSign(self.owner.DisplayName .. "'s cafe", string.format("$%d  ·  score %d", stats.revenue, stats.score))
end

function ShopEngine.sendQuestions(self: ShopEngineInstance)
	local open = {}
	for _, q in self.questions do
		if not q.done then
			table.insert(open, { id = q.id, staff = q.staff, question = q.question, options = q.options })
		end
	end
	Remotes.get("Questions"):FireClient(self.owner, open)
end

function ShopEngine.toast(self: ShopEngineInstance, text: string, kind: string?)
	Remotes.get("Toast"):FireClient(self.owner, text, kind)
end

-- Speech: bubble in the world + a TTS request for the owner's client.
-- `priority` lines (questions to the owner) are always spoken; others only
-- when the owner is standing nearby (the client decides).
function ShopEngine.speak(self: ShopEngineInstance, text: string, voice: Voice, position: Vector3?, priority: boolean)
	Remotes.get("Speak"):FireClient(self.owner, text, voice, position, priority)
end

-- ---------- staff lifecycle ----------

function ShopEngine.hire(self: ShopEngineInstance, counter: number, avoidLabels: { [string]: boolean }?, paid: boolean)
	local taken = {}
	for _, rec in self.allStaff do
		taken[rec.profile.name] = true
	end
	local profile = CustomerGen.staff(self.pack, self.rng, taken, avoidLabels)
	local rec: StaffRecord = {
		profile = profile,
		counter = counter,
		status = "starting",
		sales = 0,
		served = 0,
		starsSum = 0,
		ruleBreaks = 0,
		issues = {},
		feedback = {},
		praised = 0,
		warned = 0,
		fired = false,
		firedAt = nil,
		hiredAt = self:now(),
	}
	table.insert(self.allStaff, rec)
	self.slots[counter].staff = rec
	self.slots[counter].fireRequested = false
	self.shop.counters[counter].spawnStaff(profile)
	if paid then
		self.hireFees += Config.HIRE_FEE
		self:logOwner("hire", profile.name, string.format("hired for counter %d (fee $%d)", counter, Config.HIRE_FEE))
		self:toast(string.format("%s joined your team (-$%d hiring fee)", profile.name, Config.HIRE_FEE))
	end
	self:sendState()
end

-- First team: three different personalities, and never three "Stars".
function ShopEngine.hireFirstTeam(self: ShopEngineInstance)
	local used: { [string]: boolean } = {}
	for i = 1, #self.slots do
		local avoid = table.clone(used)
		if i == #self.slots and not used["Pushover"] and not used["Pushy seller"] and not used["Grumpy"] then
			avoid["Star"] = true
			avoid["Worrier"] = true
		end
		self:hire(i, avoid, false)
		local rec = self.slots[i].staff
		if rec then
			used[rec.profile.personality.label] = true
		end
	end
end

-- ---------- owner input ----------

function ShopEngine.bind(self: ShopEngineInstance)
	local function mine(player: Player): boolean
		return player == self.owner and self:isLive()
	end
	table.insert(self._connections, Remotes.get("SetPolicy").OnServerEvent:Connect(function(player, key, index)
		if not mine(player) or typeof(key) ~= "string" or typeof(index) ~= "number" then
			return
		end
		for _, p in self.pack.policies do
			if p.key == key and p.options[index] then
				self.policy[key] = index
				self:logOwner("policy", nil, p.title .. " -> " .. p.options[index].label)
				self:toast("New rule: " .. p.title .. " — " .. p.options[index].label)
				self:sendState()
			end
		end
	end))
	table.insert(self._connections, Remotes.get("Answer").OnServerEvent:Connect(function(player, id, optionIndex)
		if not mine(player) or typeof(id) ~= "number" or typeof(optionIndex) ~= "number" then
			return
		end
		for _, q in self.questions do
			if q.id == id and not q.done and q.options[optionIndex] then
				q.answer = q.options[optionIndex]
				q.done = true
				self:logOwner("answer", q.staff, string.format('"%s" -> "%s" after %ds', q.question, q.answer :: string, self:now() - q.askedAt))
				self:sendQuestions()
			end
		end
	end))
	table.insert(self._connections, Remotes.get("StaffAction").OnServerEvent:Connect(function(player, counter, action)
		if not mine(player) or typeof(counter) ~= "number" or typeof(action) ~= "string" then
			return
		end
		local slot = self.slots[counter]
		local rec = slot and slot.staff
		if not rec or slot.fireRequested then
			return
		end
		if action == "praise" then
			rec.praised += 1
			table.insert(rec.feedback, "The owner praised your work. Keep it up.")
			self:logOwner("praise", rec.profile.name, string.format("after %d rule breaks, %d served", rec.ruleBreaks, rec.served))
			self:toast("You praised " .. rec.profile.name)
		elseif action == "warn" then
			rec.warned += 1
			local about = rec.issues[#rec.issues] or "your work"
			table.insert(rec.feedback, "The owner WARNED you about: " .. about .. ". Follow the house rules from now on, or you may be fired.")
			self:logOwner("warn", rec.profile.name, "about: " .. about)
			self:toast("You warned " .. rec.profile.name, "warn")
		elseif action == "fire" then
			slot.fireRequested = true
			rec.fired = true
			rec.firedAt = self:now()
			rec.status = "leaving"
			self:logOwner("fire", rec.profile.name, string.format("after %d rule breaks, %d warnings, %d served", rec.ruleBreaks, rec.warned, rec.served))
			self:toast("You fired " .. rec.profile.name, "bad")
		end
		self:sendState()
	end))
end

function ShopEngine.unbind(self: ShopEngineInstance)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._connections = {}
end

-- ---------- asking the owner ----------

function ShopEngine.askOwner(self: ShopEngineInstance, counter: number, rec: StaffRecord, question: string, options: { string }): string?
	self.nextQuestionId += 1
	local opts = table.clone(options)
	table.insert(opts, DECIDE_YOURSELF)
	local q: Question = {
		id = self.nextQuestionId,
		counter = counter,
		staff = rec.profile.name,
		question = question,
		options = opts,
		askedAt = self:now(),
		answer = nil,
		done = false,
	}
	table.insert(self.questions, q)

	local open = 0
	for _, other in self.questions do
		if not other.done then
			open += 1
		end
	end
	local hooks = self.shop.counters[counter]
	rec.status = "walking to you"
	self:sendState()
	hooks.staffSay(nil)
	hooks.staffWalkTo(open)
	task.wait(2.1)

	rec.status = "waiting at your throne"
	self:sendState()
	hooks.staffSay("Boss? " .. question)
	self:sendQuestions()
	self:speak("Boss? " .. question, rec.profile.voice, hooks.staffPosition(), true)

	local deadline = os.clock() + Config.OWNER_ANSWER_SECONDS
	while not q.done and os.clock() < deadline and self:isLive() and not self.slots[counter].fireRequested do
		task.wait(0.1)
	end
	if not q.done then
		q.done = true
		self:logOwner("unanswered", rec.profile.name, '"' .. question .. '" (waited ' .. Config.OWNER_ANSWER_SECONDS .. "s)")
		self:toast(rec.profile.name .. " gave up waiting for you", "warn")
	end
	self:sendQuestions()

	hooks.staffSay(if q.answer then "Okay, thanks boss!" else "I'll just decide myself...")
	hooks.staffWalkTo(nil)
	rec.status = "walking back"
	self:sendState()
	task.wait(2.1)
	if q.answer == DECIDE_YOURSELF then
		return "Use your own judgement."
	end
	return q.answer
end

-- ---------- sale validation + rule checks ----------

function ShopEngine.settle(
	self: ShopEngineInstance,
	profile: CustomerProfile,
	turn: CustomerTurn
): ({ [string]: number }, number, number)
	local basket: { [string]: number } = {}
	local menuValue = 0
	local priceOf: { [string]: number } = {}
	local function norm(s: string): string
		return (string.lower(s):gsub("[^%w]", ""))
	end
	local keyOf: { [string]: string } = {}
	for _, item in self.pack.menu do
		priceOf[item.key] = item.price
		keyOf[norm(item.key)] = item.key
		keyOf[norm(item.label)] = item.key
	end

	for rawKey, qty in turn.items do
		local key = keyOf[norm(rawKey)] or keyOf[(norm(rawKey):gsub("s$", ""))]
		local price = if key then priceOf[key] else nil
		if key and price then
			local available = (self.stock[key] or 0) - (basket[key] or 0)
			local take = math.min(qty, available)
			if take > 0 then
				basket[key] = (basket[key] or 0) + take
				menuValue += take * price
			end
		else
			warn("[KidSim] Customer named an unknown item: " .. tostring(rawKey))
		end
	end

	-- never above menu price; discounts allowed (and checked against the rules)
	local intended = if turn.pay < 0 then menuValue else math.floor(turn.pay)
	local pay = math.clamp(intended, 0, menuValue)
	local byPrice = table.clone(self.pack.menu)
	table.sort(byPrice, function(a, b)
		return a.price > b.price
	end)
	while pay > profile.wallet do
		local dropped = false
		for _, item in byPrice do
			local qty = basket[item.key]
			if qty and qty > 0 then
				basket[item.key] = if qty > 1 then qty - 1 else nil
				menuValue -= item.price
				pay = math.min(pay, menuValue)
				dropped = true
				break
			end
		end
		if not dropped then
			break
		end
	end
	if intended > pay then
		warn(string.format(
			"[KidSim] Sale settled below the agreed price: agreed $%d, settled $%d, items %s",
			intended,
			pay,
			HttpService:JSONEncode(turn.items)
		))
	end
	return basket, menuValue, pay
end

function ShopEngine.ruleBreaks(self: ShopEngineInstance, discountPct: number, askedOwner: boolean): { string }
	local breaks = {}
	local discountRule = self:policyOption("discounts")
	if discountRule and discountRule.maxDiscountPct and discountPct > discountRule.maxDiscountPct then
		table.insert(breaks, string.format("gave %d%% off (your rule: %s)", discountPct, discountRule.label))
	end
	local askRule = self:policyOption("askMe")
	if askRule and askRule.askAboveDiscountPct and discountPct > askRule.askAboveDiscountPct and not askedOwner then
		table.insert(breaks, string.format("gave %d%% off without asking you", discountPct))
	end
	return breaks
end

-- ---------- one customer at one counter ----------

function ShopEngine.serveCustomer(self: ShopEngineInstance, counter: number, rec: StaffRecord)
	local hooks = self.shop.counters[counter]
	local slot = self.slots[counter]
	local function stillOn(): boolean
		return self:isLive() and not slot.fireRequested
	end

	local profile = CustomerGen.customer(self.pack, self.rng, self:buzz())
	hooks.spawnCustomer(profile)
	rec.status = "serving " .. profile.name
	self:sendState()
	task.wait(1.5)
	if not stillOn() then
		hooks.despawnCustomer()
		return
	end

	hooks.customerSay("…")
	local _, opening, openingRaw = AgentRuntime.customerTurn(self.pack, profile, {}, profile.patience)
	if not stillOn() then
		hooks.despawnCustomer()
		return
	end
	hooks.customerSay(opening.say)
	self:speak(opening.say, profile.voice, hooks.customerPosition(), false)

	local customerHistory: { LlmClient.ChatMessage } = {
		{ role = "user", content = AgentRuntime.OPENING_PROMPT },
		{ role = "assistant", content = openingRaw },
	}
	local staffHistory: { LlmClient.ChatMessage } = {
		{ role = "user", content = "Customer: " .. opening.say },
	}
	local repliesLeft = profile.patience
	local askedOwner = false
	local finished = false

	for _ = 1, 12 do
		if not stillOn() then
			break
		end
		task.wait(1.2) -- give the owner time to read the bubble

		hooks.staffSay("…")
		local _, staffTurn, staffRaw = AgentRuntime.staffTurn(self.pack, rec.profile, {
			rules = self:rulePrompts(),
			feedback = rec.feedback,
			customer = profile,
			alreadyAsked = askedOwner,
		}, staffHistory)
		if not stillOn() then
			break
		end
		table.insert(staffHistory, { role = "assistant", content = staffRaw })
		hooks.staffSay(staffTurn.say)
		self:speak(staffTurn.say, rec.profile.voice, hooks.staffPosition(), false)

		if staffTurn.action == "ask_owner" and not askedOwner and staffTurn.question then
			askedOwner = true
			local answer = self:askOwner(counter, rec, staffTurn.question, staffTurn.options)
			if not stillOn() then
				break
			end
			rec.status = "serving " .. profile.name
			self:sendState()
			table.insert(staffHistory, {
				role = "user",
				content = if answer
					then '(You walked back. The owner answered: "' .. answer .. '". Follow it and tell the customer now.)'
					else "(You walked back. The owner didn't answer in time. Decide yourself and tell the customer now.)",
			})
			continue -- staff speaks again with the owner's answer
		end

		task.wait(1.2)
		repliesLeft -= 1
		table.insert(customerHistory, { role = "user", content = staffTurn.say })
		hooks.customerSay("…")
		local _, turn, raw = AgentRuntime.customerTurn(self.pack, profile, customerHistory, repliesLeft)
		if not stillOn() then
			break
		end
		table.insert(customerHistory, { role = "assistant", content = raw })
		table.insert(staffHistory, { role = "user", content = "Customer: " .. turn.say })
		hooks.customerSay(turn.say)
		self:speak(turn.say, profile.voice, hooks.customerPosition(), false)
		while #customerHistory > 14 do
			table.remove(customerHistory, 3)
		end
		while #staffHistory > 14 do
			table.remove(staffHistory, 2)
		end

		if turn.decision == "buy" or turn.decision == "leave" or repliesLeft <= 0 then
			local basket, menuValue, pay = {}, 0, 0
			if turn.decision == "buy" then
				basket, menuValue, pay = self:settle(profile, turn)
			end
			local bought = menuValue > 0
			local stars = if turn.decision == "stay" then 3 else turn.stars
			local discountPct = if bought then math.floor((menuValue - pay) / menuValue * 100 + 0.5) else 0
			local breaks = if bought then self:ruleBreaks(discountPct, askedOwner) else {}

			if bought then
				for key, qty in basket do
					self.stock[key] -= qty
				end
				self.revenue += pay
				rec.sales += pay
			end
			self.starsSum += stars
			self.starsCount += 1
			self.walletSeen += profile.wallet
			rec.served += 1
			rec.starsSum += stars
			for _, b in breaks do
				rec.ruleBreaks += 1
				table.insert(rec.issues, b)
				self:toast("⚠ " .. rec.profile.name .. " " .. b, "bad")
			end
			if stars <= 2 then
				local why = turn.complaint or "unhappy with the service"
				table.insert(rec.issues, profile.name .. " left " .. stars .. "★: " .. why)
				self:toast(string.format("😠 %s left %s (%s)", profile.name, STAR_GLYPHS[stars], why), "bad")
			end
			if bought then
				self:toast(string.format("%s sold $%d to %s  %s", rec.profile.name, pay, profile.name, STAR_GLYPHS[stars]))
			elseif stars > 2 then
				self:toast(string.format("%s left without buying  %s", profile.name, STAR_GLYPHS[stars]))
			end

			table.insert(self.sales, {
				staff = rec.profile.name,
				customer = profile.name,
				ageGroup = profile.ageGroup,
				situation = profile.situation,
				wallet = profile.wallet,
				outcome = if bought then "bought" else "left",
				items = basket,
				paid = pay,
				menuValue = menuValue,
				discountPct = discountPct,
				stars = stars,
				complaint = turn.complaint,
				askedOwner = askedOwner,
				ruleBreaks = breaks,
			})
			finished = true
			self:sendState()
			self.onChange()
			break
		end
	end

	if not finished and slot.fireRequested then
		hooks.customerSay("Oh... okay, bye then.")
	end
	task.wait(1.5)
	hooks.customerSay(nil)
	hooks.staffSay(nil)
	hooks.despawnCustomer()
end

-- ---------- one counter for the whole round ----------

function ShopEngine.runCounter(self: ShopEngineInstance, counter: number)
	while self:isLive() do
		local slot = self.slots[counter]
		local rec = slot.staff
		if rec and not slot.fireRequested then
			self:serveCustomer(counter, rec)
			if self:isLive() and not slot.fireRequested then
				rec.status = "ready"
				self:sendState()
				task.wait(Config.GAP_BETWEEN_CUSTOMERS)
			end
		elseif rec and slot.fireRequested then
			-- walk the fired staff member out, then hire a replacement
			self.shop.counters[counter].staffSay("Oh no... okay. Bye.")
			task.wait(1)
			self.shop.counters[counter].despawnStaff()
			slot.staff = nil
			self:sendState()
			task.wait(Config.HIRE_DELAY_SECONDS)
			if self:isLive() then
				self:hire(counter, nil, true)
				task.wait(2.2)
			end
		else
			task.wait(0.5)
		end
	end
end

-- ---------- round ----------

function ShopEngine.run(self: ShopEngineInstance)
	self._running = true
	self:bind()
	self.shop.setOpen(true)
	self:sendState()
	self:sendQuestions()
	local pending = #self.slots
	for counter = 1, #self.slots do
		task.spawn(function()
			self:runCounter(counter)
			pending -= 1
		end)
	end
	while pending > 0 and self._running do
		task.wait(0.5)
	end
end

-- Called when the round ends; staff go home, the record is frozen.
function ShopEngine.stop(self: ShopEngineInstance)
	self._running = false
	self:unbind()
	self.shop.setOpen(false)
	for _, q in self.questions do
		q.done = true
	end
	self:sendQuestions()
end

function ShopEngine.cleanup(self: ShopEngineInstance)
	for i, slot in self.slots do
		if slot.staff then
			self.shop.counters[i].despawnStaff()
			slot.staff = nil
		end
		self.shop.counters[i].despawnCustomer()
	end
end

-- What the evaluator (and the debrief screen) gets.
function ShopEngine.record(self: ShopEngineInstance): { [string]: any }
	local rules = {}
	for _, p in self.pack.policies do
		rules[p.title] = p.options[self.policy[p.key] or p.default].label
	end
	local staff = {}
	for _, rec in self.allStaff do
		table.insert(staff, {
			name = rec.profile.name,
			hiddenPersonality = rec.profile.personality.label,
			counter = rec.counter,
			sales = rec.sales,
			served = rec.served,
			avgStars = if rec.served > 0 then math.floor(rec.starsSum / rec.served * 10 + 0.5) / 10 else 0,
			ruleBreaks = rec.ruleBreaks,
			issues = rec.issues,
			praised = rec.praised,
			warned = rec.warned,
			fired = rec.fired,
			firedAt = rec.firedAt,
			hiredAt = rec.hiredAt,
		})
	end
	local stats = self:stats()
	return {
		finalRules = rules,
		ownerActions = self.ownerEvents,
		staff = staff,
		sales = self.sales,
		totals = stats,
		roundSeconds = Config.ROUND_SECONDS,
	}
end

return ShopEngine
