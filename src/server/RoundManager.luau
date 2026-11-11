--!strict
-- Multiplayer round flow, shared by everyone in the server:
--   lobby -> countdown -> running (timed) -> results -> lobby
-- Each player owns one counter lane. A LaneEngine runs per player per
-- round; the leaderboard compares everyone's score live and at the end.
-- Players who join mid-round get a lane but wait for the next round.

local Players = game:GetService("Players")

local Types = require(game.ReplicatedStorage.Shared.Types)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local LaneEngine = require(script.Parent.LaneEngine)
local AgentRuntime = require(script.Parent.AgentRuntime)
local Config = require(script.Parent.Config)

type Pack = Types.Pack
type LeaderboardRow = Types.LeaderboardRow
type LaneHooks = LaneEngine.LaneHooks
type LaneEngineInstance = LaneEngine.LaneEngineInstance

type World = { lanes: { LaneHooks }, setOpen: (open: boolean) -> () }

local RoundManager = {}

function RoundManager.start(pack: Pack, world: World)
	local phase = "lobby"
	local laneOwner: { [number]: Player } = {}
	local laneOf: { [Player]: number } = {}
	local engines: { [Player]: LaneEngineInstance } = {}
	local endsAt = 0
	local lastResults: { [string]: any }? = nil

	-- ---------- lanes ----------

	local function resetSign(index: number)
		local owner = laneOwner[index]
		world.lanes[index].setSign(if owner then owner.DisplayName else "Counter " .. index, if owner then "ready" else "open")
	end

	local function assignLane(player: Player): number?
		if laneOf[player] then
			return laneOf[player]
		end
		for index = 1, #world.lanes do
			if laneOwner[index] == nil then
				laneOwner[index] = player
				laneOf[player] = index
				resetSign(index)
				return index
			end
		end
		return nil
	end

	local function releaseLane(player: Player)
		local index = laneOf[player]
		if index then
			laneOwner[index] = nil
			laneOf[player] = nil
			resetSign(index)
		end
	end

	local function placeCharacter(player: Player)
		local index = laneOf[player]
		local character = player.Character
		if not index or not character then
			return
		end
		local root = character:WaitForChild("HumanoidRootPart", 5)
		if root then
			character:PivotTo(world.lanes[index].spawnCFrame)
		end
	end

	-- ---------- broadcasting ----------

	local function leaderboard(): { LeaderboardRow }
		local rows: { LeaderboardRow } = {}
		for index, player in laneOwner do
			local engine = engines[player]
			local stats = if engine then engine:stats() else { revenue = 0, avgStars = 0, served = 0, score = 0, walletSeen = 0 }
			table.insert(rows, {
				userId = player.UserId,
				name = player.DisplayName,
				lane = index,
				revenue = stats.revenue,
				avgStars = stats.avgStars,
				served = stats.served,
				score = stats.score,
			})
		end
		table.sort(rows, function(a, b)
			if a.score ~= b.score then
				return a.score > b.score
			end
			return a.lane < b.lane
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
			roundSeconds = Config.ROUND_SECONDS,
			lane = laneOf[player],
			lanesFull = laneOf[player] == nil,
		}
	end

	local function sendPhaseTo(player: Player)
		if phase == "lobby" then
			Remotes.get("Phase"):FireClient(player, "lobby", lobbyPayload(player))
		elseif phase == "countdown" or phase == "running" or phase == "closing" then
			if engines[player] then
				Remotes.get("Phase"):FireClient(player, phase, { lane = laneOf[player] })
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
		world.setOpen(false)
		for _, engine in engines do
			engine:stop()
		end
		sendPhaseAll()

		local finalBoard = leaderboard()
		local rankOf: { [number]: number } = {}
		for rank, row in finalBoard do
			rankOf[row.userId] = rank
		end

		-- evaluate every lane in parallel
		local pending = 0
		for player, engine in engines do
			pending += 1
			task.spawn(function()
				local stats = engine:stats()
				local evaluation = AgentRuntime.evaluate(pack, engine.records, {
					revenue = stats.revenue,
					averageStars = stats.avgStars,
					customersServed = stats.served,
					moneyInTheirWallets = stats.walletSeen,
					score = stats.score,
					rank = rankOf[player.UserId],
					players = #finalBoard,
				})
				if player.Parent == Players then
					Remotes.get("Debrief"):FireClient(player, {
						leaderboard = finalBoard,
						rank = rankOf[player.UserId],
						stats = stats,
						records = engine.records,
						menu = pack.menu,
						evaluation = evaluation,
						thesis = pack.thesis,
						title = pack.title,
					})
				end
				pending -= 1
			end)
		end
		local waitedSince = os.clock()
		while pending > 0 and os.clock() - waitedSince < 40 do
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
		endsAt = os.clock() + Config.COUNTDOWN_SECONDS + Config.ROUND_SECONDS
		for index, player in laneOwner do
			placeCharacter(player)
			engines[player] = LaneEngine.new(pack, player, world.lanes[index], endsAt, broadcastLeaderboard)
		end
		sendPhaseAll()
		broadcastLeaderboard()
		for remaining = Config.COUNTDOWN_SECONDS, 1, -1 do
			Remotes.get("Timer"):FireAllClients(remaining, "countdown")
			task.wait(1)
		end

		phase = "running"
		world.setOpen(true)
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
		for index in laneOwner do
			resetSign(index)
		end
		sendPhaseAll()
		broadcastLeaderboard()
	end

	-- ---------- players ----------

	local function onPlayerAdded(player: Player)
		assignLane(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.2)
			placeCharacter(player)
		end)
		if player.Character then
			task.spawn(placeCharacter, player)
		end
		-- give the client a moment to hook its remotes
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
		end
		releaseLane(player)
		broadcastLeaderboard()
	end)

	Remotes.get("StartRound").OnServerEvent:Connect(function(player)
		if phase == "lobby" and laneOf[player] then
			task.spawn(startRound)
		end
	end)
	Remotes.get("Continue").OnServerEvent:Connect(function()
		backToLobby()
	end)
end

return RoundManager
