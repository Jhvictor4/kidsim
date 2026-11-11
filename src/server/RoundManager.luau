--!strict
-- Multiplayer round flow, shared by everyone in the server:
--   lobby -> countdown -> running (timed) -> closing -> results -> lobby
-- Each player owns one shop. A ShopEngine runs per owner per round; the
-- leaderboard compares owners live and at the end. Players who join
-- mid-round get a shop but wait for the next round.

local Players = game:GetService("Players")

local Types = require(game.ReplicatedStorage.Shared.Types)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local ShopEngine = require(script.Parent.ShopEngine)
local AgentRuntime = require(script.Parent.AgentRuntime)
local Config = require(script.Parent.Config)

type Pack = Types.Pack
type LeaderboardRow = Types.LeaderboardRow
type ShopHooks = ShopEngine.ShopHooks
type ShopEngineInstance = ShopEngine.ShopEngineInstance

type World = { shops: { ShopHooks } }

local RoundManager = {}

function RoundManager.start(pack: Pack, world: World)
	local phase = "lobby"
	local shopOwner: { [number]: Player } = {}
	local shopOf: { [Player]: number } = {}
	local engines: { [Player]: ShopEngineInstance } = {}
	local endsAt = 0
	local lastResults: { [string]: any }? = nil

	-- what the client needs to draw the rule chips
	local policyDefs = {}
	for _, p in pack.policies do
		local labels = {}
		for _, option in p.options do
			table.insert(labels, option.label)
		end
		table.insert(policyDefs, { key = p.key, title = p.title, options = labels, default = p.default })
	end

	-- ---------- shops ----------

	local function resetSign(index: number)
		local owner = shopOwner[index]
		world.shops[index].setSign(if owner then owner.DisplayName .. "'s cafe" else "Shop " .. index, if owner then "ready" else "for rent")
	end

	local function assignShop(player: Player): number?
		if shopOf[player] then
			return shopOf[player]
		end
		for index = 1, #world.shops do
			if shopOwner[index] == nil then
				shopOwner[index] = player
				shopOf[player] = index
				resetSign(index)
				return index
			end
		end
		return nil
	end

	local function releaseShop(player: Player)
		local index = shopOf[player]
		if index then
			shopOwner[index] = nil
			shopOf[player] = nil
			resetSign(index)
		end
	end

	-- put the owner on their throne
	local function seatOwner(player: Player)
		local index = shopOf[player]
		local character = player.Character
		if not index or not character then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
		local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
		if not humanoid or not root then
			return
		end
		local throne = world.shops[index].throne
		character:PivotTo(throne.CFrame + Vector3.new(0, 3, 0))
		task.wait(0.2)
		pcall(function()
			throne:Sit(humanoid :: Humanoid)
		end)
	end

	-- ---------- broadcasting ----------

	local function leaderboard(): { LeaderboardRow }
		local rows: { LeaderboardRow } = {}
		for index, player in shopOwner do
			local engine = engines[player]
			local stats = if engine then engine:stats() else nil
			table.insert(rows, {
				userId = player.UserId,
				name = player.DisplayName,
				shop = index,
				revenue = if stats then stats.revenue else 0,
				avgStars = if stats then stats.avgStars else 0,
				served = if stats then stats.served else 0,
				score = if stats then stats.score else 0,
			})
		end
		table.sort(rows, function(a, b)
			if a.score ~= b.score then
				return a.score > b.score
			end
			return a.shop < b.shop
		end)
		return rows
	end

	local function broadcastLeaderboard()
		Remotes.get("Leaderboard"):FireAllClients(leaderboard())
	end

	local function lobbyPayload(player: Player): { [string]: any }
		return {
			title = pack.title,
			thesis = pack.thesis,
			briefing = pack.briefing,
			menu = pack.menu,
			policies = policyDefs,
			roundSeconds = Config.ROUND_SECONDS,
			shop = shopOf[player],
			shopsFull = shopOf[player] == nil,
		}
	end

	local function sendPhaseTo(player: Player)
		if phase == "lobby" then
			Remotes.get("Phase"):FireClient(player, "lobby", lobbyPayload(player))
		elseif phase == "countdown" or phase == "running" or phase == "closing" then
			if engines[player] then
				Remotes.get("Phase"):FireClient(player, phase, { shop = shopOf[player], policies = policyDefs })
			else
				Remotes.get("Phase"):FireClient(player, "waiting", lobbyPayload(player))
			end
		elseif phase == "results" then
			Remotes.get("Phase"):FireClient(player, "waiting", lobbyPayload(player))
			if lastResults then
				Remotes.get("Debrief"):FireClient(player, { leaderboard = lastResults.leaderboard })
			end
		end
		Remotes.get("Leaderboard"):FireClient(player, leaderboard())
	end

	local function sendPhaseAll()
		for _, player in Players:GetPlayers() do
			sendPhaseTo(player)
		end
	end

	-- ---------- round ----------

	local function finishRound()
		phase = "closing"
		for _, engine in engines do
			engine:stop()
		end
		sendPhaseAll()

		local finalBoard = leaderboard()
		local rankOf: { [number]: number } = {}
		for rank, row in finalBoard do
			rankOf[row.userId] = rank
		end

		local pending = 0
		for player, engine in engines do
			pending += 1
			task.spawn(function()
				local record = engine:record()
				record.rank = rankOf[player.UserId]
				record.players = #finalBoard
				local evaluation = AgentRuntime.evaluate(pack, record)
				if player.Parent == Players then
					Remotes.get("Debrief"):FireClient(player, {
						leaderboard = finalBoard,
						rank = rankOf[player.UserId],
						stats = engine:stats(),
						staff = record.staff,
						rules = record.finalRules,
						evaluation = evaluation,
						thesis = pack.thesis,
						title = pack.title,
					})
				end
				engine:cleanup()
				pending -= 1
			end)
		end
		local waitedSince = os.clock()
		while pending > 0 and os.clock() - waitedSince < 45 do
			task.wait(0.2)
		end

		lastResults = { leaderboard = finalBoard }
		phase = "results"
		for _, player in Players:GetPlayers() do
			if not engines[player] then
				sendPhaseTo(player)
			end
		end
	end

	local function startRound()
		if phase ~= "lobby" then
			return
		end
		phase = "countdown"
		engines = {}
		local startedAt = os.clock() + Config.COUNTDOWN_SECONDS
		endsAt = startedAt + Config.ROUND_SECONDS
		for index, player in shopOwner do
			task.spawn(seatOwner, player)
			local engine = ShopEngine.new(pack, player, world.shops[index], startedAt, endsAt, broadcastLeaderboard)
			engines[player] = engine
			engine:hireFirstTeam() -- staff walk in during the countdown
		end
		sendPhaseAll()
		broadcastLeaderboard()
		for remaining = Config.COUNTDOWN_SECONDS, 1, -1 do
			Remotes.get("Timer"):FireAllClients(remaining, "countdown")
			task.wait(1)
		end

		phase = "running"
		sendPhaseAll()
		for _, engine in engines do
			task.spawn(function()
				engine:run()
			end)
		end
		while os.clock() < endsAt do
			Remotes.get("Timer"):FireAllClients(math.max(0, math.ceil(endsAt - os.clock())), "running")
			task.wait(1)
		end
		Remotes.get("Timer"):FireAllClients(0, "running")
		finishRound()
	end

	local function backToLobby()
		if phase ~= "results" then
			return
		end
		phase = "lobby"
		engines = {}
		lastResults = nil
		for index in shopOwner do
			resetSign(index)
		end
		sendPhaseAll()
		broadcastLeaderboard()
	end

	-- ---------- players ----------

	local function onPlayerAdded(player: Player)
		assignShop(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.3)
			seatOwner(player)
		end)
		if player.Character then
			task.spawn(seatOwner, player)
		end
		task.delay(1, function()
			if player.Parent == Players then
				sendPhaseTo(player)
				broadcastLeaderboard()
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	-- Play Solo can join the player before the connection above exists
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local engine = engines[player]
		if engine then
			engine:stop()
			engine:cleanup()
		end
		releaseShop(player)
		broadcastLeaderboard()
	end)

	Remotes.get("StartRound").OnServerEvent:Connect(function(player)
		if phase == "lobby" and shopOf[player] then
			task.spawn(startRound)
		end
	end)
	Remotes.get("Continue").OnServerEvent:Connect(function()
		backToLobby()
	end)
end

return RoundManager
