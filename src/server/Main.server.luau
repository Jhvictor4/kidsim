--!strict
-- Boot: create remotes, build the world (one counter lane per possible
-- player), and hand everything to the RoundManager. Swapping ACTIVE_PACK to
-- a different module is the whole "new scenario" story — the engine does
-- not change.

local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local WorldBuilder = require(script.Parent.WorldBuilder)
local RoundManager = require(script.Parent.RoundManager)
local LlmClient = require(script.Parent.LlmClient)
local Config = require(script.Parent.Config)

local ACTIVE_PACK = require(script.Parent.Packs.CafeShift)

Remotes.init()
local world = WorldBuilder.build(ACTIVE_PACK, Config.MAX_LANES)

print("[KidSim] Pack loaded: " .. ACTIVE_PACK.title .. " (" .. ACTIVE_PACK.id .. ")")
print("[KidSim] LLM configured: " .. tostring(LlmClient.isConfigured()))

RoundManager.start(ACTIVE_PACK, world)
