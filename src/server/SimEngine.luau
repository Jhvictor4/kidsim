--!strict
-- Pack-agnostic simulation engine. Loads a scenario pack, owns the
-- authoritative world state, runs Intro -> Shift (events) -> Close ->
-- Debrief, and keeps a shift log the evaluator can read.
--
-- Nothing in this file may name a cafe concept. State keys, meters,
-- inventory, prompts and incidents all come from the pack.

local Types = require(game.ReplicatedStorage.Shared.Types)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local AgentRuntime = require(script.Parent.AgentRuntime)
local Config = require(script.Parent.Config)

type Pack = Types.Pack
type PackEvent = Types.PackEvent
type Choice = Types.Choice
type Deltas = Types.Deltas
type LogEntry = Types.LogEntry

export type WorldHooks = {
	spawnCounterpart: (event: PackEvent) -> (),
	despawnCounterpart: () -> (),
	setOpen: (open: boolean) -> (),
}

type Action = { kind: string, text: string?, choiceId: string? }

local SimEngine = {}
SimEngine.__index = SimEngine

export type SimEngineInstance = typeof(setmetatable(
	{} :: {
		pack: Pack,
		player: Player,
		world: WorldHooks,
		state: { meters: { [string]: number }, inventory: { [string]: number } },
		initialState: { meters: { [string]: number }, inventory: { [string]: number } },
		log: { LogEntry },
		_queue: { Action },
		_connections: { RBXScriptConnection },
		_running: boolean,
	},
	SimEngine
))

local function deepCopyNumbers(source: { [string]: number }): { [string]: number }
	local copy = {}
	for key, value in source do
		copy[key] = value
	end
	return copy
end

function SimEngine.new(pack: Pack, player: Player, world: WorldHooks): SimEngineInstance
	local self = setmetatable({
		pack = pack,
		player = player,
		world = world,
		state = {
			meters = deepCopyNumbers(pack.initialState.meters),
			inventory = deepCopyNumbers(pack.initialState.inventory),
		},
		initialState = {
			meters = deepCopyNumbers(pack.initialState.meters),
			inventory = deepCopyNumbers(pack.initialState.inventory),
		},
		log = {},
		_queue = {},
		_connections = {},
		_running = false,
	}, SimEngine)
	return self :: SimEngineInstance
end

-- ---------- replication helpers ----------

function SimEngine.sendPhase(self: SimEngineInstance, phase: string, payload: any)
	Remotes.get("Phase"):FireClient(self.player, phase, payload)
end

function SimEngine.sendState(self: SimEngineInstance)
	Remotes.get("State"):FireClient(self.player, {
		meters = self.state.meters,
		inventory = self.state.inventory,
	})
end

function SimEngine.sendDialogue(self: SimEngineInstance, speaker: string, text: string, kind: string?)
	Remotes.get("Dialogue"):FireClient(self.player, speaker, text, kind or "npc")
end

function SimEngine.sendChoices(self: SimEngineInstance, choices: { { id: string, label: string } })
	Remotes.get("Choices"):FireClient(self.player, choices)
end

function SimEngine.sendToast(self: SimEngineInstance, text: string)
	Remotes.get("Toast"):FireClient(self.player, text)
end

function SimEngine.sendBusy(self: SimEngineInstance, busy: boolean)
	Remotes.get("Busy"):FireClient(self.player, busy)
end

-- ---------- state mutation ----------

local function describeDelta(self: SimEngineInstance, deltas: Deltas): string
	local bits = {}
	if deltas.meters then
		for key, delta in deltas.meters do
			if delta ~= 0 then
				local label = key
				local format = "number"
				for _, meter in self.pack.meters do
					if meter.key == key then
						label = meter.label
						format = meter.format
						break
					end
				end
				local sign = delta > 0 and "+" or "-"
				local absValue = math.abs(delta)
				if format == "currency" then
					table.insert(bits, sign .. "$" .. tostring(absValue) .. " " .. label)
				else
					table.insert(bits, sign .. tostring(absValue) .. " " .. label)
				end
			end
		end
	end
	if deltas.inventory then
		for key, delta in deltas.inventory do
			if delta ~= 0 then
				local label = self.pack.inventoryLabels[key] or key
				local sign = delta > 0 and "+" or ""
				table.insert(bits, sign .. tostring(delta) .. " " .. label)
			end
		end
	end
	return table.concat(bits, "  ")
end

function SimEngine.applyDeltas(self: SimEngineInstance, deltas: Deltas)
	if deltas.meters then
		for key, delta in deltas.meters do
			local value = (self.state.meters[key] or 0) + delta
			for _, meter in self.pack.meters do
				if meter.key == key and meter.max then
					value = math.min(value, meter.max)
				end
			end
			self.state.meters[key] = math.max(0, value)
		end
	end
	if deltas.inventory then
		for key, delta in deltas.inventory do
			self.state.inventory[key] = math.max(0, (self.state.inventory[key] or 0) + delta)
		end
	end
	self:sendState()
	local summary = describeDelta(self, deltas)
	if #summary > 0 then
		self:sendToast(summary)
	end
end

-- ---------- player input plumbing ----------

function SimEngine.bind(self: SimEngineInstance)
	local function push(action: Action)
		table.insert(self._queue, action)
	end
	table.insert(self._connections, Remotes.get("Say").OnServerEvent:Connect(function(player, text)
		if player == self.player and typeof(text) == "string" and #text > 0 then
			push({ kind = "say", text = string.sub(text, 1, 300) })
		end
	end))
	table.insert(self._connections, Remotes.get("Choose").OnServerEvent:Connect(function(player, choiceId)
		if player == self.player and typeof(choiceId) == "string" then
			push({ kind = "choose", choiceId = choiceId })
		end
	end))
	table.insert(self._connections, Remotes.get("RequestHint").OnServerEvent:Connect(function(player)
		if player == self.player then
			push({ kind = "hint" })
		end
	end))
	table.insert(self._connections, Remotes.get("Continue").OnServerEvent:Connect(function(player)
		if player == self.player then
			push({ kind = "continue" })
		end
	end))
end

function SimEngine.unbind(self: SimEngineInstance)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._connections = {}
end

function SimEngine.waitForAction(self: SimEngineInstance): Action
	while self._running do
		if #self._queue > 0 then
			return table.remove(self._queue, 1) :: Action
		end
		task.wait(0.05)
	end
	return { kind = "stopped" }
end

function SimEngine.waitForContinue(self: SimEngineInstance)
	while self._running do
		local action = self:waitForAction()
		if action.kind == "continue" or action.kind == "stopped" then
			return
		end
	end
end

-- ---------- incident loop ----------

local function availableChoices(self: SimEngineInstance, event: PackEvent): { Choice }
	local choices = {}
	for _, choice in event.choices do
		local okStock = true
		if choice.requires then
			for key, needed in choice.requires do
				if (self.state.inventory[key] or 0) < needed then
					okStock = false
					break
				end
			end
		end
		if okStock then
			table.insert(choices, choice)
		end
	end
	return choices
end

function SimEngine.runIncident(self: SimEngineInstance, event: PackEvent)
	self.world.spawnCounterpart(event)
	self:sendPhase("incident", { title = event.title, counterpart = event.counterpart.name })
	task.wait(0.8)
	self:sendDialogue(event.counterpart.name, event.opening)

	local choices = availableChoices(self, event)
	local choiceButtons = {}
	for _, choice in choices do
		table.insert(choiceButtons, { id = choice.id, label = choice.label })
	end
	self:sendChoices(choiceButtons)

	local history: { { role: string, content: string } } = {
		{ role = "assistant", content = event.opening },
	}
	local playerSaid: { string } = {}
	local hintsUsed = 0

	while self._running do
		local action = self:waitForAction()

		if action.kind == "say" and action.text then
			table.insert(playerSaid, action.text)
			table.insert(history, { role = "user", content = action.text })
			self:sendDialogue(self.player.DisplayName, action.text, "player")
			self:sendBusy(true)
			local reply = AgentRuntime.counterpartReply(self.pack, event, self.state, history, action.text)
			self:sendBusy(false)
			table.insert(history, { role = "assistant", content = reply })
			self:sendDialogue(event.counterpart.name, reply)
			-- keep the history bounded
			while #history > 10 do
				table.remove(history, 1)
			end
		elseif action.kind == "hint" then
			if hintsUsed < Config.COACH_HINTS_PER_INCIDENT then
				hintsUsed += 1
				self:sendBusy(true)
				local hint = AgentRuntime.coachHint(self.pack, event, self.state)
				self:sendBusy(false)
				Remotes.get("CoachHint"):FireClient(self.player, hint)
			else
				Remotes.get("CoachHint"):FireClient(self.player, "That's your one hint for this moment — your call now.")
			end
		elseif action.kind == "choose" and action.choiceId then
			local chosen: Choice? = nil
			for _, choice in choices do
				if choice.id == action.choiceId then
					chosen = choice
					break
				end
			end
			if chosen then
				self:applyDeltas(chosen.deltas)
				self:sendDialogue(event.counterpart.name, chosen.reaction)
				table.insert(self.log, {
					eventId = event.id,
					eventTitle = event.title,
					playerSaid = playerSaid,
					choiceId = chosen.id,
					logLine = chosen.logLine,
					lessonTag = chosen.lessonTag,
				})
				break
			end
		elseif action.kind == "stopped" then
			return
		end
	end

	self:sendChoices({})
	task.wait(2.2)
	self.world.despawnCounterpart()
	task.wait(0.6)
end

-- ---------- full run ----------

function SimEngine.run(self: SimEngineInstance)
	self._running = true
	self:bind()

	self:sendPhase("intro", {
		title = self.pack.title,
		thesis = self.pack.thesis,
		briefing = self.pack.briefing,
		meters = self.pack.meters,
		inventoryLabels = self.pack.inventoryLabels,
		skillTags = self.pack.skillTags,
	})
	self:sendState()
	self:waitForContinue()
	if not self._running then
		return
	end

	self.world.setOpen(true)
	self:sendPhase("shift", { eventCount = #self.pack.events })
	self:sendState() -- re-send after the client built its HUD

	for _, event in self.pack.events do
		if not self._running then
			return
		end
		self:runIncident(event)
	end

	self.world.setOpen(false)
	self:sendPhase("close", {
		initialMeters = self.initialState.meters,
		finalMeters = self.state.meters,
	})
	self:sendBusy(true)

	local evaluation = AgentRuntime.evaluate(self.pack, self.initialState, self.state, self.log)
	self:sendBusy(false)

	Remotes.get("Debrief"):FireClient(self.player, {
		evaluation = evaluation,
		initialMeters = self.initialState.meters,
		finalMeters = self.state.meters,
		meters = self.pack.meters,
		thesis = self.pack.thesis,
		title = self.pack.title,
		log = self.log,
	})
	self:sendPhase("debrief", {})

	-- wait for "play again"
	self:waitForContinue()
	self:unbind()
	self._running = false
end

function SimEngine.stop(self: SimEngineInstance)
	self._running = false
	self:unbind()
end

return SimEngine
