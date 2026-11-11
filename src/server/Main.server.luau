--!strict
-- Boot: create remotes, build the world from the active pack, and run one
-- engine session per joining player (demo targets a single player).
-- Swapping ACTIVE_PACK to a different module is the whole "new scenario"
-- story — the engine does not change.

local Players = game:GetService("Players")

local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local SimEngine = require(script.Parent.SimEngine)
local WorldBuilder = require(script.Parent.WorldBuilder)
local LlmClient = require(script.Parent.LlmClient)

local ACTIVE_PACK = require(script.Parent.Packs.CafeShift)

Remotes.init()
local world = WorldBuilder.build(ACTIVE_PACK.menuText)

print("[KidSim] Pack loaded: " .. ACTIVE_PACK.title .. " (" .. ACTIVE_PACK.id .. ")")
print("[KidSim] LLM configured: " .. tostring(LlmClient.isConfigured()))

local sessions: { [Player]: any } = {}

local function runSessionLoop(player: Player)
	while player.Parent == Players do
		local engine = SimEngine.new(ACTIVE_PACK, player, world)
		sessions[player] = engine
		engine:run() -- returns after the player presses "play again" at Debrief
		if player.Parent ~= Players then
			break
		end
		task.wait(0.5)
	end
	sessions[player] = nil
end

local function startSession(player: Player)
	if sessions[player] ~= nil then
		return
	end
	sessions[player] = false -- reserve before the engine exists (double-start guard)
	task.spawn(runSessionLoop, player)
end

Players.PlayerAdded:Connect(startSession)
-- Play Solo can join the player before the connection above exists
for _, player in Players:GetPlayers() do
	startSession(player)
end

Players.PlayerRemoving:Connect(function(player)
	local engine = sessions[player]
	if engine then
		engine:stop()
		sessions[player] = nil
	end
end)
