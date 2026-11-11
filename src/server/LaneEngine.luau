--!strict
-- One player's counter for one timed round. Pulls random customers from
-- CustomerGen, lets the child talk to each customer agent, and turns the
-- agent's proposed decision into a validated sale (menu price, stock,
-- wallet). Keeps the authoritative revenue / stars / stock and a record of
-- every customer for the evaluator.
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
type CustomerTurn = Types.CustomerTurn
type SaleRecord = Types.SaleRecord

export type LaneHooks = {
	spawnCustomer: (profile: CustomerProfile) -> (),
	despawnCustomer: () -> (),
	setSign: (title: string, subtitle: string) -> (),
	showBubble: (text: string?) -> (),
	spawnCFrame: CFrame,
	cameraCFrame: CFrame,
}

export type LaneStats = {
	revenue: number,
	avgStars: number,
	served: number,
	score: number,
	walletSeen: number, -- total money in the wallets of finished customers
}

type Action = { kind: string, text: string? }

local LaneEngine = {}
LaneEngine.__index = LaneEngine

export type LaneEngineInstance = typeof(setmetatable(
	{} :: {
		pack: Pack,
		player: Player,
		lane: LaneHooks,
		endsAt: number,
		onChange: () -> (),
		rng: Random,
		stock: { [string]: number },
		revenue: number,
		starsSum: number,
		starsCount: number,
		walletSeen: number,
		records: { SaleRecord },
		lastName: string?,
		_queue: { Action },
		_connections: { RBXScriptConnection },
		_running: boolean,
	},
	LaneEngine
))

local STAR_GLYPHS = { "★☆☆☆☆", "★★☆☆☆", "★★★☆☆", "★★★★☆", "★★★★★" }

function LaneEngine.new(pack: Pack, player: Player, lane: LaneHooks, endsAt: number, onChange: () -> ()): LaneEngineInstance
	local stock = {}
	for key, count in pack.initialStock do
		stock[key] = count
	end
	local self = setmetatable({
		pack = pack,
		player = player,
		lane = lane,
		endsAt = endsAt,
		onChange = onChange,
		rng = Random.new(),
		stock = stock,
		revenue = 0,
		starsSum = 0,
		starsCount = 0,
		walletSeen = 0,
		records = {},
		lastName = nil,
		_queue = {},
		_connections = {},
		_running = false,
	}, LaneEngine)
	return self :: LaneEngineInstance
end

-- ---------- stats ----------

function LaneEngine.stats(self: LaneEngineInstance): LaneStats
	local starBonus = self.starsSum - 3 * self.starsCount
	return {
		revenue = self.revenue,
		avgStars = if self.starsCount > 0 then self.starsSum / self.starsCount else 0,
		served = self.starsCount,
		score = self.revenue + Config.STARS_WEIGHT * starBonus,
		walletSeen = self.walletSeen,
	}
end

-- Word of mouth: happier customers so far -> fuller wallets next.
function LaneEngine.buzz(self: LaneEngineInstance): number
	if self.starsCount == 0 then
		return 1
	end
	local avg = self.starsSum / self.starsCount
	return math.clamp(1 + Config.BUZZ_PER_STAR * (avg - 3), Config.BUZZ_MIN, Config.BUZZ_MAX)
end

-- ---------- replication ----------

function LaneEngine.sendState(self: LaneEngineInstance)
	local stats = self:stats()
	Remotes.get("State"):FireClient(self.player, {
		revenue = stats.revenue,
		avgStars = stats.avgStars,
		served = stats.served,
		score = stats.score,
		stock = self.stock,
		buzz = self:buzz(),
	})
	self.lane.setSign(self.player.DisplayName, string.format("$%d  ·  score %d", stats.revenue, stats.score))
end

function LaneEngine.say(self: LaneEngineInstance, speaker: string, text: string, kind: string)
	Remotes.get("Dialogue"):FireClient(self.player, speaker, text, kind)
	if kind == "npc" then
		self.lane.showBubble(text)
	end
end

function LaneEngine.toast(self: LaneEngineInstance, text: string)
	Remotes.get("Toast"):FireClient(self.player, text)
end

function LaneEngine.busy(self: LaneEngineInstance, busy: boolean, who: string?)
	Remotes.get("Busy"):FireClient(self.player, busy, who)
	if busy then
		self.lane.showBubble("…")
	end
end

-- ---------- input ----------

function LaneEngine.bind(self: LaneEngineInstance)
	table.insert(self._connections, Remotes.get("Say").OnServerEvent:Connect(function(player, text)
		if player == self.player and typeof(text) == "string" and #text > 0 then
			table.insert(self._queue, { kind = "say", text = string.sub(text, 1, 300) })
		end
	end))
	table.insert(self._connections, Remotes.get("RequestHint").OnServerEvent:Connect(function(player)
		if player == self.player then
			table.insert(self._queue, { kind = "hint" })
		end
	end))
end

function LaneEngine.unbind(self: LaneEngineInstance)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._connections = {}
end

function LaneEngine.timeLeft(self: LaneEngineInstance): number
	return self.endsAt - os.clock()
end

function LaneEngine.isLive(self: LaneEngineInstance): boolean
	return self._running and self:timeLeft() > 0 and self.player.Parent == Players
end

-- Next action, or nil on idle timeout / round end.
function LaneEngine.waitForAction(self: LaneEngineInstance, timeout: number): Action?
	local deadline = os.clock() + timeout
	while self:isLive() and os.clock() < deadline do
		if #self._queue > 0 then
			return table.remove(self._queue, 1)
		end
		task.wait(0.05)
	end
	return nil
end

-- ---------- sale validation ----------

-- Turn the agent's proposed basket into what can really happen: only menu
-- items, capped by stock, trimmed (priciest first) to fit the wallet, and
-- never charged above menu price.
function LaneEngine.settle(
	self: LaneEngineInstance,
	profile: CustomerProfile,
	turn: CustomerTurn
): ({ [string]: number }, number, number, { string })
	local notes: { string } = {}
	local basket: { [string]: number } = {}
	local menuValue = 0
	local priceOf: { [string]: number } = {}
	local labelOf: { [string]: string } = {}
	for _, item in self.pack.menu do
		priceOf[item.key] = item.price
		labelOf[item.key] = item.label
	end

	-- agents write keys loosely ("hot chocolate", "Cookies"): match on key or
	-- label, ignoring case, spaces, punctuation and a plural "s"
	local function norm(s: string): string
		return (string.lower(s):gsub("[^%w]", ""))
	end
	local keyOf: { [string]: string } = {}
	for _, item in self.pack.menu do
		keyOf[norm(item.key)] = item.key
		keyOf[norm(item.label)] = item.key
	end

	for rawKey, qty in turn.items do
		local key = keyOf[norm(rawKey)] or keyOf[(norm(rawKey):gsub("s$", ""))]
		local price = if key then priceOf[key] else nil
		if key and price then
			local available = (self.stock[key] or 0) - (basket[key] or 0)
			local take = math.min(qty, available)
			if take < qty then
				table.insert(notes, "Out of " .. labelOf[key] .. "!")
			end
			if take > 0 then
				basket[key] = (basket[key] or 0) + take
				menuValue += take * price
			end
		else
			warn("[KidSim] Customer named an unknown item: " .. tostring(rawKey))
		end
	end

	-- never charged above menu price; a discount the shopkeeper offered is fine
	local intended = if turn.pay < 0 then menuValue else math.floor(turn.pay)
	local pay = math.clamp(intended, 0, menuValue)

	-- wallet cap on what they actually hand over: if the agreed price doesn't
	-- fit, drop the priciest unit until it does
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
	return basket, menuValue, pay, notes
end

function LaneEngine.record(
	self: LaneEngineInstance,
	profile: CustomerProfile,
	playerSaid: { string },
	outcome: string,
	basket: { [string]: number },
	paid: number,
	menuValue: number,
	stars: number
)
	self.starsSum += stars
	self.starsCount += 1
	self.walletSeen += profile.wallet
	table.insert(self.records, {
		customer = profile.name,
		ageGroup = profile.ageGroup,
		situation = profile.situation,
		taste = profile.taste,
		sensitivity = profile.sensitivity.label,
		wallet = profile.wallet,
		playerSaid = playerSaid,
		outcome = outcome,
		items = basket,
		paid = paid,
		menuValue = menuValue,
		stars = stars,
	})
	self:sendState()
	self.onChange()
end

-- ---------- one customer ----------

function LaneEngine.serveCustomer(self: LaneEngineInstance)
	local profile = CustomerGen.generate(self.pack, self.rng, self:buzz(), self.lastName)
	self.lastName = profile.name
	self.lane.spawnCustomer(profile)
	Remotes.get("Customer"):FireClient(self.player, CustomerGen.visible(profile))
	task.wait(1.4) -- walk to the counter

	if not self:isLive() then
		self.lane.despawnCustomer()
		return
	end

	self:busy(true, profile.name)
	local _, opening, openingRaw = AgentRuntime.customerTurn(self.pack, profile, {}, profile.patience)
	self:busy(false)
	self:say(profile.name, opening.say, "npc")

	local history: { LlmClient.ChatMessage } = {
		{ role = "user", content = AgentRuntime.OPENING_PROMPT },
		{ role = "assistant", content = openingRaw },
	}
	local transcript: { string } = { profile.name .. ": " .. opening.say }
	local playerSaid: { string } = {}
	local repliesLeft = profile.patience
	local hintsUsed = 0

	while true do
		local action = self:waitForAction(Config.CUSTOMER_IDLE_SECONDS)
		if not self:isLive() then
			break -- round over mid-conversation: not scored
		end

		if action == nil then
			self:say(profile.name, "I'll come back another time.", "npc")
			self:record(profile, playerSaid, "timeout", {}, 0, 0, 2)
			self:toast("Customer left waiting  " .. STAR_GLYPHS[2])
			break
		elseif action.kind == "hint" then
			if hintsUsed < Config.COACH_HINTS_PER_CUSTOMER then
				hintsUsed += 1
				local hint = AgentRuntime.coachHint(self.pack, profile, transcript)
				Remotes.get("CoachHint"):FireClient(self.player, hint)
			else
				Remotes.get("CoachHint"):FireClient(self.player, "That's your one hint for this customer — your call now.")
			end
		elseif action.kind == "say" and action.text then
			local text = action.text
			repliesLeft -= 1
			table.insert(playerSaid, text)
			table.insert(transcript, "Shopkeeper: " .. text)
			table.insert(history, { role = "user", content = text })
			self:say(self.player.DisplayName, text, "player")

			self:busy(true, profile.name)
			local _, turn, raw = AgentRuntime.customerTurn(self.pack, profile, history, repliesLeft)
			self:busy(false)
			if not self:isLive() then
				break
			end

			table.insert(history, { role = "assistant", content = raw })
			table.insert(transcript, profile.name .. ": " .. turn.say)
			while #history > 14 do
				table.remove(history, 3) -- keep the opening exchange, drop the oldest middle turns
			end
			self:say(profile.name, turn.say, "npc")

			if turn.decision == "buy" then
				local basket, menuValue, pay, notes = self:settle(profile, turn)
				for _, note in notes do
					self:toast(note)
				end
				if menuValue == 0 then
					self:record(profile, playerSaid, "left", {}, 0, 0, turn.stars)
					self:toast("No sale  " .. STAR_GLYPHS[turn.stars])
				else
					for key, qty in basket do
						self.stock[key] -= qty
					end
					self.revenue += pay
					self:record(profile, playerSaid, "bought", basket, pay, menuValue, turn.stars)
					local discount = if pay < menuValue then string.format(" (gave $%d off)", menuValue - pay) else ""
					self:toast(string.format("+$%d%s  %s", pay, discount, STAR_GLYPHS[turn.stars]))
				end
				break
			elseif turn.decision == "leave" or repliesLeft <= 0 then
				local stars = if turn.decision == "leave" then turn.stars else 3
				self:record(profile, playerSaid, "left", {}, 0, 0, stars)
				self:toast("No sale  " .. STAR_GLYPHS[stars])
				break
			end
		end
	end

	Remotes.get("Customer"):FireClient(self.player, nil)
	task.wait(1.2)
	self.lane.despawnCustomer()
end

-- ---------- round ----------

function LaneEngine.run(self: LaneEngineInstance)
	self._running = true
	self:bind()
	self:sendState()
	while self:isLive() do
		self:serveCustomer()
		if self:isLive() then
			task.wait(Config.GAP_BETWEEN_CUSTOMERS)
		end
	end
	self.lane.despawnCustomer()
	self:unbind()
	self._running = false
end

function LaneEngine.stop(self: LaneEngineInstance)
	self._running = false
	self:unbind()
end

return LaneEngine
