--!strict
-- All player-facing UI, built from code. The player is the cafe OWNER:
--   * lobby card, round timer + HUD, live leaderboard;
--   * "Your staff" cards (status, sales, stars, rule breaks) with
--     Praise / Warn / Fire buttons;
--   * house-rule chips (click to cycle) — no typing anywhere;
--   * question cards when a staff member walks over to the throne;
--   * text-to-speech for what staff and customers say (silent fallback);
--   * results + the sim-to-real debrief that reveals who each staff member
--     really was.
-- Staff/customer lines appear as speech bubbles in the world (server side).
--
-- Every UIListLayout sorts by LayoutOrder (the engine default is Name,
-- which silently reorders siblings that share a class name). Key widgets
-- carry stable Names so tests can target them by path.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

-- WaitForChild: on a live server the client can run before Shared replicates
local Remotes = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- The default Roblox chat window/input bar sat over the middle of the screen;
-- nothing in this game is typed, so switch both off.
pcall(function()
	local TextChatService = game:GetService("TextChatService")
	TextChatService.ChatWindowConfiguration.Enabled = false
	TextChatService.ChatInputBarConfiguration.Enabled = false
end)
pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
end)

-- ---------- palette ----------
local INK = Color3.fromRGB(34, 32, 29)
local PAPER = Color3.fromRGB(248, 243, 234)
local MUTED = Color3.fromRGB(130, 122, 110)
local SOFT = Color3.fromRGB(100, 92, 80)
local ACCENT = Color3.fromRGB(214, 124, 48)
local GOOD = Color3.fromRGB(62, 142, 94)
local BAD = Color3.fromRGB(186, 70, 60)
local WARN = Color3.fromRGB(214, 150, 40)
local GOLD = Color3.fromRGB(226, 172, 52)
local WHITE = Color3.fromRGB(255, 255, 255)

local LOOK_COLORS: { [string]: Color3 } = {
	white = Color3.fromRGB(235, 235, 230),
	brown = Color3.fromRGB(140, 95, 60),
	navy = Color3.fromRGB(90, 120, 190),
	olive = Color3.fromRGB(140, 150, 80),
}

-- ---------- tiny UI helpers ----------

local function round(instance: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 10)
	corner.Parent = instance
end

local function pad(instance: GuiObject, all: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, all)
	padding.PaddingBottom = UDim.new(0, all)
	padding.PaddingLeft = UDim.new(0, all)
	padding.PaddingRight = UDim.new(0, all)
	padding.Parent = instance
end

local function list(parent: Instance, horizontal: boolean, gap: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

local function label(parent: Instance, text: string, size: number, color: Color3?, bold: boolean?, order: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextSize = size
	l.TextColor3 = color or INK
	l.Text = text
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.LayoutOrder = order or 0
	l.Parent = parent
	return l
end

-- full-width, auto-height paragraph
local function para(parent: Instance, text: string, size: number, color: Color3?, bold: boolean?, order: number?): TextLabel
	local l = label(parent, text, size, color, bold, order)
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	return l
end

local function button(parent: Instance, name: string, text: string, bg: Color3, fg: Color3, order: number?): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.TextColor3 = fg
	b.BackgroundColor3 = bg
	b.AutoButtonColor = true
	b.Text = text
	b.LayoutOrder = order or 0
	b.Parent = parent
	round(b, 8)
	return b
end

local function panel(parent: Instance, name: string, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color or PAPER
	f.BackgroundTransparency = 0.04
	f.Parent = parent
	round(f, 12)
	return f
end

local function money(n: number): string
	return (if n < 0 then "-$" else "$") .. tostring(math.abs(math.floor(n + 0.5)))
end

local function stars(avg: number): string
	if avg <= 0 then
		return "–"
	end
	return string.format("%.1f★", avg)
end

local function clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function clock(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- ---------- root ----------

local gui = Instance.new("ScreenGui")
gui.Name = "KidSimUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local policyDefs: { any } = {}
local currentPolicy: { [string]: number } = {}

-- ---------- HUD (top centre) ----------

local hud = panel(gui, "HUD")
hud.AnchorPoint = Vector2.new(0.5, 0)
hud.Position = UDim2.new(0.5, 0, 0, 10)
hud.Size = UDim2.new(0, 0, 0, 46)
hud.AutomaticSize = Enum.AutomaticSize.X
hud.Visible = false
pad(hud, 8)
list(hud, true, 16).VerticalAlignment = Enum.VerticalAlignment.Center

local function chip(title: string, order: number): TextLabel
	local c = Instance.new("Frame")
	c.Name = title
	c.BackgroundTransparency = 1
	c.AutomaticSize = Enum.AutomaticSize.XY
	c.LayoutOrder = order
	c.Parent = hud
	list(c, false, 0)
	label(c, string.upper(title), 10, MUTED, true, 1).AutomaticSize = Enum.AutomaticSize.XY
	local value = label(c, "–", 19, INK, true, 2)
	value.AutomaticSize = Enum.AutomaticSize.XY
	return value
end

local timeValue = chip("Time", 1)
local revenueValue = chip("Revenue", 2)
local starsValue = chip("Stars", 3)
local scoreValue = chip("Score", 4)

-- ---------- leaderboard (top right) ----------

local board = panel(gui, "Leaderboard", INK)
board.AnchorPoint = Vector2.new(1, 0)
board.Position = UDim2.new(1, -12, 0, 10)
board.Size = UDim2.new(0, 230, 0, 0)
board.AutomaticSize = Enum.AutomaticSize.Y
board.BackgroundTransparency = 0.15
pad(board, 10)
list(board, false, 4)
label(board, "LEADERBOARD", 11, GOLD, true, 0).Size = UDim2.new(1, 0, 0, 14)
local boardRows = Instance.new("Frame")
boardRows.Name = "Rows"
boardRows.BackgroundTransparency = 1
boardRows.Size = UDim2.new(1, 0, 0, 0)
boardRows.AutomaticSize = Enum.AutomaticSize.Y
boardRows.LayoutOrder = 1
boardRows.Parent = board
list(boardRows, false, 2)

Remotes.get("Leaderboard").OnClientEvent:Connect(function(rows: { any })
	clear(boardRows)
	for rank, row in rows do
		local mine = row.userId == player.UserId
		local text = string.format("%d. %s   %s  %s   %d pts", rank, row.name, money(row.revenue), stars(row.avgStars), row.score)
		local l = para(boardRows, text, 13, if mine then GOLD else PAPER, mine, rank)
		l.Font = if mine then Enum.Font.GothamBold else Enum.Font.Gotham
	end
	board.Visible = #rows > 0
end)

-- ---------- toasts (event feed) ----------

local toastArea = Instance.new("Frame")
toastArea.AnchorPoint = Vector2.new(0.5, 0)
toastArea.Position = UDim2.new(0.5, 0, 0, 64)
toastArea.Size = UDim2.new(0, 440, 0, 120)
toastArea.BackgroundTransparency = 1
toastArea.Parent = gui
list(toastArea, false, 4).HorizontalAlignment = Enum.HorizontalAlignment.Center

local toastCount = 0
Remotes.get("Toast").OnClientEvent:Connect(function(text: string, kind: string?)
	toastCount += 1
	local toast = Instance.new("TextLabel")
	toast.LayoutOrder = toastCount
	toast.BackgroundColor3 = if kind == "bad" then BAD elseif kind == "warn" then WARN else INK
	toast.BackgroundTransparency = 0.1
	toast.TextColor3 = Color3.fromRGB(255, 244, 222)
	toast.Font = Enum.Font.GothamBold
	toast.TextSize = 14
	toast.Text = "  " .. text .. "  "
	toast.AutomaticSize = Enum.AutomaticSize.XY
	toast.Parent = toastArea
	round(toast, 8)
	task.delay(if kind == "bad" then 5 else 3.5, function()
		TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.delay(0.5, function()
			toast:Destroy()
		end)
	end)
end)

-- ---------- your staff (left) ----------

local staffPanel = Instance.new("Frame")
staffPanel.Name = "StaffPanel"
staffPanel.Position = UDim2.new(0, 12, 0, 70)
staffPanel.Size = UDim2.new(0, 250, 0, 0)
staffPanel.AutomaticSize = Enum.AutomaticSize.Y
staffPanel.BackgroundTransparency = 1
staffPanel.Visible = false
staffPanel.Parent = gui
list(staffPanel, false, 6)
para(staffPanel, "YOUR STAFF", 11, WHITE, true, 0).TextStrokeTransparency = 0.5

local staffCards: { Frame } = {}
for i = 1, 3 do
	local card = panel(staffPanel, "Staff" .. i)
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = i
	pad(card, 8)
	list(card, false, 2)
	staffCards[i] = card
end

local function renderStaff(cards: { any })
	for i, card in staffCards do
		clear(card)
		local info = cards[i]
		if not info then
			card.Visible = false
			continue
		end
		card.Visible = true
		if info.hiring then
			para(card, string.format("Counter %d — hiring someone new…", info.counter), 13, MUTED, true, 1)
			continue
		end
		local title = para(card, "", 15, INK, true, 1)
		title.RichText = true
		local dot = LOOK_COLORS[info.look] or MUTED
		title.Text = string.format(
			'<font color="#%s">●</font> %s  <font size="12" color="#827A6E">counter %d</font>',
			dot:ToHex(),
			info.name,
			info.counter
		)
		para(card, info.status or "", 12, SOFT, false, 2)
		para(card, string.format("%s sold · %s · %d served", money(info.sales), stars(info.avgStars), info.served), 13, INK, false, 3)
		if info.ruleBreaks > 0 or info.lastIssue then
			local issue = para(card, "", 12, BAD, true, 4)
			issue.Text = (if info.ruleBreaks > 0 then string.format("⚠ %d rule break%s", info.ruleBreaks, if info.ruleBreaks == 1 then "" else "s") else "⚠")
				.. (if info.lastIssue then " — " .. info.lastIssue else "")
		end
		if info.warned > 0 or info.praised > 0 then
			para(card, string.format("praised %d · warned %d", info.praised, info.warned), 11, MUTED, false, 5)
		end
		if info.leaving then
			para(card, "Leaving the shop…", 12, BAD, true, 6)
			continue
		end
		local row = Instance.new("Frame")
		row.Name = "Actions"
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 26)
		row.LayoutOrder = 7
		row.Parent = card
		list(row, true, 6)
		local actions = {
			{ "PraiseButton", "Praise", GOOD, "praise" },
			{ "WarnButton", "Warn", WARN, "warn" },
			{ "FireButton", "Fire", BAD, "fire" },
		}
		for order, a in actions do
			local b = button(row, a[1], a[2], a[3], WHITE, order)
			b.TextSize = 13
			b.Size = UDim2.new(1 / 3, -4, 1, 0)
			local counter = info.counter
			b.Activated:Connect(function()
				Remotes.get("StaffAction"):FireServer(counter, a[4])
			end)
		end
	end
end

-- ---------- house rules (bottom) ----------

local rulesBar = panel(gui, "Rules", INK)
rulesBar.AnchorPoint = Vector2.new(0.5, 1)
rulesBar.Position = UDim2.new(0.5, 0, 1, -10)
rulesBar.Size = UDim2.new(0, 0, 0, 0)
rulesBar.AutomaticSize = Enum.AutomaticSize.XY
rulesBar.BackgroundTransparency = 0.2
rulesBar.Visible = false
pad(rulesBar, 8)
local rulesLayout = list(rulesBar, true, 8)
rulesLayout.VerticalAlignment = Enum.VerticalAlignment.Center
local rulesTitle = label(rulesBar, "HOUSE RULES\n(click to change)", 10, GOLD, true, 0)
rulesTitle.AutomaticSize = Enum.AutomaticSize.XY

local ruleButtons: { [string]: TextButton } = {}

local function renderRules()
	for _, def in policyDefs do
		local b = ruleButtons[def.key]
		if not b then
			b = button(rulesBar, "Rule_" .. def.key, "", PAPER, INK, #ruleButtons + 1)
			b.AutomaticSize = Enum.AutomaticSize.X
			b.Size = UDim2.new(0, 0, 0, 34)
			b.TextSize = 13
			local p = Instance.new("UIPadding")
			p.PaddingLeft = UDim.new(0, 10)
			p.PaddingRight = UDim.new(0, 10)
			p.Parent = b
			local key = def.key
			b.Activated:Connect(function()
				local count = 0
				for _, d in policyDefs do
					if d.key == key then
						count = #d.options
					end
				end
				local nextIndex = ((currentPolicy[key] or 1) % count) + 1
				currentPolicy[key] = nextIndex
				Remotes.get("SetPolicy"):FireServer(key, nextIndex)
			end)
			ruleButtons[def.key] = b
		end
		local index = currentPolicy[def.key] or def.default
		b.Text = def.title .. ": " .. (def.options[index] or "?") .. "  »"
	end
end

-- ---------- staff questions (bottom centre, above the rules) ----------

local questionCard = panel(gui, "QuestionCard", PAPER)
questionCard.AnchorPoint = Vector2.new(0.5, 1)
questionCard.Position = UDim2.new(0.5, 0, 1, -64)
questionCard.Size = UDim2.new(0, 460, 0, 0)
questionCard.AutomaticSize = Enum.AutomaticSize.Y
questionCard.Visible = false
pad(questionCard, 12)
list(questionCard, false, 6)
local stroke = Instance.new("UIStroke")
stroke.Color = GOLD
stroke.Thickness = 3
stroke.Parent = questionCard

local function renderQuestions(open: { any })
	clear(questionCard)
	local q = open[1]
	if not q then
		questionCard.Visible = false
		return
	end
	questionCard.Visible = true
	para(questionCard, string.upper(q.staff) .. " IS ASKING YOU", 11, ACCENT, true, 1)
	para(questionCard, q.question, 17, INK, true, 2)
	for i, option in q.options do
		local b = button(questionCard, "Option" .. i, option, if i == #q.options then MUTED else INK, PAPER, 2 + i)
		b.Size = UDim2.new(1, 0, 0, 32)
		b.TextSize = 14
		b.TextWrapped = true
		local id = q.id
		b.Activated:Connect(function()
			Remotes.get("Answer"):FireServer(id, i)
		end)
	end
	if #open > 1 then
		para(questionCard, string.format("+%d more waiting at your throne", #open - 1), 12, MUTED, false, 10)
	end
end
Remotes.get("Questions").OnClientEvent:Connect(renderQuestions)

Remotes.get("State").OnClientEvent:Connect(function(state)
	revenueValue.Text = money(state.revenue)
	starsValue.Text = stars(state.avgStars)
	scoreValue.Text = tostring(state.score)
	if state.policy then
		for key, index in state.policy do
			currentPolicy[key] = index
		end
		renderRules()
	end
	renderStaff(state.staff or {})
end)

-- ---------- text-to-speech ----------
-- Roblox AudioTextToSpeech (no uploaded assets needed). Questions to the
-- owner are always spoken; other lines only when the owner walks near the
-- speaker. Any failure falls back to text only, silently.

local tts: any = nil
local ttsDisabled = false
local ttsFailures = 0
local ttsQueue: { any } = {}
local ttsRecent: { number } = {}
local TTS_PER_MINUTE = 6 -- the experience-wide limit is 1 + 6 x players per minute
local NEAR_STUDS = 24

local function setupTts(): boolean
	if tts then
		return true
	end
	local ok, err = pcall(function()
		local generator = Instance.new("AudioTextToSpeech")
		pcall(function()
			generator.AutoLocalize = false -- keep it in English, matching the bubble
		end)
		local output = Instance.new("AudioDeviceOutput")
		local wire = Instance.new("Wire")
		wire.SourceInstance = generator
		wire.TargetInstance = output
		generator.Parent = SoundService
		output.Parent = SoundService
		wire.Parent = SoundService
		tts = generator
	end)
	if not ok then
		ttsDisabled = true
		warn("[KidSim] Text-to-speech unavailable: " .. tostring(err))
	end
	return ok
end

local function ttsBudgetLeft(): boolean
	local now = os.clock()
	for i = #ttsRecent, 1, -1 do
		if now - ttsRecent[i] > 60 then
			table.remove(ttsRecent, i)
		end
	end
	return #ttsRecent < TTS_PER_MINUTE
end

task.spawn(function()
	while true do
		local job = table.remove(ttsQueue, 1)
		if not job or ttsDisabled then
			task.wait(0.2)
			continue
		end
		if not setupTts() or not ttsBudgetLeft() then
			continue
		end
		table.insert(ttsRecent, os.clock())
		local generator = tts
		local ok, status = pcall(function()
			generator.Text = string.sub(job.text, 1, 300)
			generator.VoiceId = job.voice.voiceId
			generator.Pitch = job.voice.pitch
			generator.Speed = job.voice.speed
			generator.Volume = 1.5
			generator.TimePosition = 0
			return generator:LoadAsync()
		end)
		if ok and status == Enum.AssetFetchStatus.Success then
			ttsFailures = 0
			generator:Play()
			local length = math.clamp(generator.TimeLength, 0.5, 20)
			local started = os.clock()
			while generator.IsPlaying and os.clock() - started < length + 1 do
				task.wait(0.1)
			end
		else
			ttsFailures += 1
			warn("[KidSim] Text-to-speech failed: " .. tostring(status))
			if ttsFailures >= 4 then
				ttsDisabled = true
				warn("[KidSim] Text-to-speech turned off after repeated failures; text bubbles only")
			else
				task.wait(5)
			end
		end
	end
end)

Remotes.get("Speak").OnClientEvent:Connect(function(text: string, voice, position: Vector3?, priority: boolean)
	if ttsDisabled or typeof(text) ~= "string" or typeof(voice) ~= "table" then
		return
	end
	if priority then
		table.insert(ttsQueue, 1, { text = text, voice = voice })
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not position or (root.Position - position).Magnitude > NEAR_STUDS then
		return
	end
	if #ttsQueue < 2 then
		table.insert(ttsQueue, { text = text, voice = voice })
	end
end)

-- ---------- overlays ----------

local function makeOverlay(name: string): Frame
	local overlay = Instance.new("Frame")
	overlay.Name = name
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(24, 22, 20)
	overlay.BackgroundTransparency = 0.12
	overlay.Visible = false
	overlay.ZIndex = 5
	overlay.Parent = gui
	return overlay
end

-- Returns the container to put rows in. For a scrolling card that is an
-- inner "Content" frame: AutomaticCanvasSize ignores a ScrollingFrame's own
-- UIPadding, which used to clip the last debrief line.
local function card(parent: Instance, name: string, width: number, scrolling: boolean): GuiObject
	local c: GuiObject
	if scrolling then
		local s = Instance.new("ScrollingFrame")
		s.ScrollBarThickness = 6
		s.AutomaticCanvasSize = Enum.AutomaticSize.Y
		s.CanvasSize = UDim2.new(0, 0, 0, 0)
		s.Size = UDim2.new(0, width, 0.86, 0)
		c = s
	else
		local f = Instance.new("Frame")
		f.Size = UDim2.new(0, width, 0, 0)
		f.AutomaticSize = Enum.AutomaticSize.Y
		c = f
	end
	c.Name = name
	c.AnchorPoint = Vector2.new(0.5, 0.5)
	c.Position = UDim2.fromScale(0.5, 0.5)
	c.BackgroundColor3 = PAPER
	c.ZIndex = 6
	c.Parent = parent
	round(c, 16)
	local content: GuiObject = c
	if scrolling then
		local inner = Instance.new("Frame")
		inner.Name = "Content"
		inner.BackgroundTransparency = 1
		inner.Size = UDim2.new(1, -8, 0, 0) -- leave room for the scrollbar
		inner.AutomaticSize = Enum.AutomaticSize.Y
		inner.ZIndex = 6
		inner.Parent = c
		content = inner
	end
	pad(content, 22)
	list(content, false, 9)
	return content
end

local function setZ(container: Instance)
	for _, d in container:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 6
		end
	end
end

-- Lobby
local lobbyOverlay = makeOverlay("LobbyOverlay")
local lobbyCard = card(lobbyOverlay, "LobbyCard", 600, false)
para(lobbyCard, "KIDSIM — ISAAC SIM FOR CHILDREN", 12, ACCENT, true, 1)
local lobbyTitle = para(lobbyCard, "", 30, INK, true, 2)
local lobbyThesis = para(lobbyCard, "", 17, SOFT, true, 3)
local lobbyBriefing = para(lobbyCard, "", 15, INK, false, 4)
local lobbyRules = para(lobbyCard, "", 13, SOFT, false, 5)
local lobbyShop = para(lobbyCard, "", 14, ACCENT, true, 6)
local startButton = button(lobbyCard, "StartButton", "Open the cafe", ACCENT, WHITE, 7)
startButton.Size = UDim2.new(1, 0, 0, 44)
startButton.TextSize = 17
startButton.Activated:Connect(function()
	Remotes.get("StartRound"):FireServer()
end)
setZ(lobbyCard)

-- Waiting banner (joined mid-round or all shops taken)
local waitingBanner = panel(gui, "WaitingBanner", INK)
waitingBanner.AnchorPoint = Vector2.new(0.5, 1)
waitingBanner.Position = UDim2.new(0.5, 0, 1, -24)
waitingBanner.Size = UDim2.new(0, 460, 0, 0)
waitingBanner.AutomaticSize = Enum.AutomaticSize.Y
waitingBanner.Visible = false
pad(waitingBanner, 12)
list(waitingBanner, false, 0)
local waitingText = para(waitingBanner, "", 16, PAPER, true, 1)
waitingText.TextXAlignment = Enum.TextXAlignment.Center

-- Countdown / closing
local bigOverlay = makeOverlay("BigOverlay")
bigOverlay.BackgroundTransparency = 0.45
local bigText = label(bigOverlay, "", 64, PAPER, true)
bigText.ZIndex = 6
bigText.AnchorPoint = Vector2.new(0.5, 0.5)
bigText.Position = UDim2.fromScale(0.5, 0.5)
bigText.Size = UDim2.new(0, 700, 0, 200)
bigText.TextXAlignment = Enum.TextXAlignment.Center

-- Debrief / results
local debriefOverlay = makeOverlay("DebriefOverlay")
local debriefCard = card(debriefOverlay, "DebriefCard", 680, true)

Remotes.get("Debrief").OnClientEvent:Connect(function(payload)
	clear(debriefCard)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local function line(text: string, size: number, color: Color3?, bold: boolean?): TextLabel
		return para(debriefCard, text, size, color, bold, nextOrder())
	end

	line("ROUND RESULTS — " .. string.upper(payload.title or "KidSim"), 12, ACCENT, true)
	local rows = payload.leaderboard or {}
	if payload.rank then
		line(string.format("Your cafe placed #%d of %d", payload.rank, #rows), 28, INK, true)
	else
		line("This round's results", 28, INK, true)
	end

	line("LEADERBOARD", 12, MUTED, true)
	for rank, row in rows do
		local mine = row.userId == player.UserId
		local l = line(
			string.format("%d. %-14s %6s   %s   %d served   %d pts", rank, row.name, money(row.revenue), stars(row.avgStars), row.served, row.score),
			15,
			if mine then ACCENT else INK,
			mine
		)
		l.Font = Enum.Font.Code
	end

	local stats = payload.stats
	if stats then
		line("YOUR CAFE", 12, MUTED, true)
		line(
			string.format(
				"%s earned · %s average · %d customers · hiring fees %s · score %d",
				money(stats.revenue),
				stars(stats.avgStars),
				stats.served,
				money(stats.hireFees),
				stats.score
			),
			16,
			INK,
			true
		)

		line("WHO YOUR STAFF REALLY WERE", 12, MUTED, true)
		for _, s in (payload.staff or {}) do
			local fate = if s.fired then string.format("fired at %s", clock(s.firedAt or 0)) else "kept"
			local color = if s.ruleBreaks > 0 and not s.fired then BAD elseif s.fired and s.ruleBreaks > 0 then GOOD else INK
			line(
				string.format(
					"%s — really a %s · %s sold · %s · %d rule break%s · %s",
					s.name,
					s.hiddenPersonality,
					money(s.sales),
					stars(s.avgStars),
					s.ruleBreaks,
					if s.ruleBreaks == 1 then "" else "s",
					fate
				),
				14,
				color,
				true
			)
		end

		-- growth since last round (remembered by GBrain)
		local growth = payload.growth
		if growth and growth.memoryOn then
			line("SINCE LAST ROUND — remembered by GBrain", 12, ACCENT, true)
			local now, before = growth.current or {}, growth.previous
			local function frac(won: number?, total: number?): string
				if not total or total == 0 then
					return "–"
				end
				return string.format("%d/%d", won or 0, total)
			end
			local function trend(a: number?, b: number?, c: number?, d: number?): string
				if not b or b == 0 or not d or d == 0 then
					return ""
				end
				local was, is = (a or 0) / b, (c or 0) / d
				return if is > was + 0.001 then "  ▲" elseif is < was - 0.001 then "  ▼" else "  ="
			end
			local rows = {
				{ "Answering your team", "answered", "asked" },
				{ "Spotting problem staff", "caught", "problemTotal" },
				{ "Warning before firing", "firedAfterWarning", "fired" },
			}
			if before then
				for _, r in rows do
					local a, b, c, d = before[r[2]], before[r[3]], now[r[2]], now[r[3]]
					line(string.format("%s:  %s last time  →  %s today%s", r[1], frac(a, b), frac(c, d), trend(a, b, c, d)), 15, INK, true)
				end
				line(
					string.format("Customer happiness:  %.1f★ → %.1f★   ·   Score:  %d → %d", before.avgStars or 0, now.avgStars or 0, before.score or 0, now.score or 0),
					15,
					INK,
					true
				)
			else
				for _, r in rows do
					line(string.format("%s:  %s today", r[1], frac(now[r[2]], now[r[3]])), 15, INK, true)
				end
				line("First round on record — next time you'll see how you've grown.", 13, SOFT, false)
			end
			if not growth.saved then
				line("(Couldn't reach the memory server this time — this round wasn't saved.)", 12, MUTED, false)
			end
		end

		local evaluation = payload.evaluation or {}
		line("SKILLS YOU PRACTICED", 12, MUTED, true)
		for _, skill in (evaluation.skills or {}) do
			line("● " .. (skill.name or skill.tag or "?"), 17, INK, true)
			local evidence = line(skill.evidence or "", 14, SOFT, false)
			local indent = Instance.new("UIPadding")
			indent.PaddingLeft = UDim.new(0, 18)
			indent.Parent = evidence
		end
		if evaluation.wentWell and #evaluation.wentWell > 0 then
			line("WHAT WENT WELL", 12, GOOD, true)
			for _, item in evaluation.wentWell do
				line("+ " .. item, 14, INK, false)
			end
		end
		if evaluation.wentWrong and #evaluation.wentWrong > 0 then
			line("WHAT TO WATCH", 12, BAD, true)
			for _, item in evaluation.wentWrong do
				line("– " .. item, 14, INK, false)
			end
		end
		line("IN THE REAL WORLD", 12, MUTED, true)
		line(evaluation.realWorldTransfer or "", 18, INK, true)
		line("NEXT DRILL", 12, MUTED, true)
		line(evaluation.nextDrill or "", 16, INK, false)
		line(payload.thesis or "", 13, ACCENT, true)
	end

	local again = button(debriefCard, "AgainButton", "Back to the lobby", INK, PAPER, nextOrder())
	again.Size = UDim2.new(1, 0, 0, 42)
	again.Activated:Connect(function()
		Remotes.get("Continue"):FireServer()
	end)
	setZ(debriefCard)
	;(debriefCard.Parent :: ScrollingFrame).CanvasPosition = Vector2.new(0, 0)

	bigOverlay.Visible = false
	debriefOverlay.Visible = true
end)

-- ---------- timer ----------

Remotes.get("Timer").OnClientEvent:Connect(function(seconds: number, kind: string)
	if kind == "countdown" then
		bigText.Text = tostring(seconds)
	else
		timeValue.Text = clock(seconds)
		timeValue.TextColor3 = if seconds <= 20 then BAD else INK
	end
end)

-- ---------- camera ----------
-- On the throne: a fixed view over the whole shop (counters, customers,
-- staff walking over). Stand up (jump) and the normal camera comes back so
-- the owner can walk around; sit back down for the big view again.

local roundActive = false

local function updateCamera()
	local cam = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if roundActive and seat and seat.Name == "Throne" then
		local at = seat.Position
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(at + Vector3.new(0, 20, -5), at + Vector3.new(0, -1, 29))
	elseif cam.CameraType == Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Custom
	end
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		humanoid:GetPropertyChangedSignal("SeatPart"):Connect(updateCamera)
		updateCamera()
	end
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	task.spawn(watchCharacter, player.Character)
end

-- ---------- phase routing ----------

local function hideAll()
	lobbyOverlay.Visible = false
	bigOverlay.Visible = false
	debriefOverlay.Visible = false
	waitingBanner.Visible = false
	hud.Visible = false
	staffPanel.Visible = false
	rulesBar.Visible = false
	questionCard.Visible = false
end

local function applyPolicies(defs: { any }?)
	if defs then
		policyDefs = defs
		for _, d in defs do
			if currentPolicy[d.key] == nil then
				currentPolicy[d.key] = d.default
			end
		end
		renderRules()
	end
end

local function applyLobby(payload)
	applyPolicies(payload.policies)
	lobbyTitle.Text = payload.title or ""
	lobbyThesis.Text = "“" .. (payload.thesis or "") .. "”"
	lobbyBriefing.Text = payload.briefing or ""
	local bits = {}
	for _, d in policyDefs do
		table.insert(bits, d.title .. ": " .. (d.options[currentPolicy[d.key] or d.default] or "?"))
	end
	lobbyRules.Text = "Starting rules — " .. table.concat(bits, " · ") .. string.format("   ·   Round: %d min", (payload.roundSeconds or 180) // 60)
	if payload.shop then
		lobbyShop.Text = "You own shop #" .. payload.shop .. ". Anyone can open the cafes for everyone."
		startButton.Visible = true
	else
		lobbyShop.Text = "All shops are taken — you're watching this time."
		startButton.Visible = false
	end
end

Remotes.get("Phase").OnClientEvent:Connect(function(phase: string, payload)
	roundActive = phase == "countdown" or phase == "running"
	updateCamera()
	if phase == "lobby" then
		hideAll()
		applyLobby(payload)
		lobbyOverlay.Visible = true
	elseif phase == "waiting" then
		applyLobby(payload)
		lobbyOverlay.Visible = false
		hud.Visible = false
		staffPanel.Visible = false
		rulesBar.Visible = false
		waitingText.Text = if payload.shopsFull
			then "All shops are taken — watching the leaderboard."
			else "A round is in progress. You'll get your shop next round!"
		waitingBanner.Visible = not debriefOverlay.Visible
	elseif phase == "countdown" then
		hideAll()
		applyPolicies(payload.policies)
		hud.Visible = true
		staffPanel.Visible = true
		rulesBar.Visible = true
		revenueValue.Text, starsValue.Text, scoreValue.Text = "$0", "–", "0"
		bigText.Text = "Your staff are arriving..."
		bigText.TextSize = 48
		bigOverlay.Visible = true
	elseif phase == "running" then
		hideAll()
		applyPolicies(payload.policies)
		hud.Visible = true
		staffPanel.Visible = true
		rulesBar.Visible = true
		task.delay(1, function()
			local tip = Instance.new("TextLabel")
			tip.LayoutOrder = -1
			tip.BackgroundColor3 = INK
			tip.BackgroundTransparency = 0.1
			tip.TextColor3 = GOLD
			tip.Font = Enum.Font.GothamBold
			tip.TextSize = 13
			tip.Text = "  Tip: jump off your throne to walk around — sit back down for the big view  "
			tip.AutomaticSize = Enum.AutomaticSize.XY
			tip.Parent = toastArea
			round(tip, 8)
			task.delay(7, function()
				tip:Destroy()
			end)
		end)
	elseif phase == "closing" then
		staffPanel.Visible = false
		rulesBar.Visible = false
		questionCard.Visible = false
		bigText.Text = "Closing time!\nYour coach is writing your debrief."
		bigText.TextSize = 30
		bigOverlay.Visible = true
	end
end)
