--!strict
-- All player-facing UI, built from code: lobby card, round timer + HUD,
-- live leaderboard, the customer conversation (free chat only — the
-- customer agent decides), one coach hint per customer, and the end-of-
-- round results + sim-to-real debrief. Pack-agnostic: the menu and copy
-- arrive in the lobby payload.
--
-- Every UIListLayout sorts by LayoutOrder (the engine default is Name,
-- which silently reorders siblings that share a class name). Key widgets
-- carry stable Names so tests can target them by path.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- WaitForChild: on a live server the client can run before Shared replicates
local Remotes = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- The default Roblox chat window/input bar sat over the middle of the screen;
-- all talking happens in our own bar, so switch both off.
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
local PAPER_DIM = Color3.fromRGB(236, 229, 216)
local MUTED = Color3.fromRGB(130, 122, 110)
local SOFT = Color3.fromRGB(100, 92, 80)
local ACCENT = Color3.fromRGB(214, 124, 48)
local GOOD = Color3.fromRGB(62, 142, 94)
local BAD = Color3.fromRGB(186, 70, 60)
local COACH = Color3.fromRGB(78, 112, 180)
local GOLD = Color3.fromRGB(226, 172, 52)

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
	b.TextSize = 16
	b.TextColor3 = fg
	b.BackgroundColor3 = bg
	b.AutoButtonColor = true
	b.Text = text
	b.LayoutOrder = order or 0
	b.Parent = parent
	round(b, 10)
	return b
end

local function panel(parent: Instance, name: string, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color or PAPER
	f.BackgroundTransparency = 0.04
	f.Parent = parent
	round(f, 14)
	return f
end

local function money(n: number): string
	return "$" .. tostring(math.floor(n + 0.5))
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

-- ---------- root ----------

local gui = Instance.new("ScreenGui")
gui.Name = "KidSimUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local menuLabels: { [string]: string } = {}

-- ---------- HUD (top centre) ----------

local hud = panel(gui, "HUD")
hud.AnchorPoint = Vector2.new(0.5, 0)
hud.Position = UDim2.new(0.5, 0, 0, 12)
hud.Size = UDim2.new(0, 0, 0, 48)
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
	label(c, string.upper(title), 11, MUTED, true, 1).AutomaticSize = Enum.AutomaticSize.XY
	local value = label(c, "–", 20, INK, true, 2)
	value.AutomaticSize = Enum.AutomaticSize.XY
	return value
end

local timeValue = chip("Time", 1)
local revenueValue = chip("Revenue", 2)
local starsValue = chip("Stars", 3)
local scoreValue = chip("Score", 4)
local stockLine: TextLabel? = nil -- lives in the talk panel, created below

Remotes.get("State").OnClientEvent:Connect(function(state)
	revenueValue.Text = money(state.revenue)
	starsValue.Text = stars(state.avgStars)
	scoreValue.Text = tostring(state.score)
	local bits = {}
	for key, count in state.stock do
		table.insert(bits, (menuLabels[key] or key) .. " " .. tostring(count))
	end
	table.sort(bits)
	if stockLine then
		stockLine.Text = "Stock left: " .. table.concat(bits, " · ")
	end
end)

-- ---------- leaderboard (top right) ----------

local board = panel(gui, "Leaderboard", INK)
board.AnchorPoint = Vector2.new(1, 0)
board.Position = UDim2.new(1, -16, 0, 12)
board.Size = UDim2.new(0, 250, 0, 0)
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

local function renderBoard(rows: { any })
	clear(boardRows)
	for rank, row in rows do
		local mine = row.userId == player.UserId
		local text = string.format("%d. %s   %s  %s   %d pts", rank, row.name, money(row.revenue), stars(row.avgStars), row.score)
		local l = para(boardRows, text, 14, if mine then GOLD else PAPER, mine, rank)
		l.Font = if mine then Enum.Font.GothamBold else Enum.Font.Gotham
	end
	board.Visible = #rows > 0
end
Remotes.get("Leaderboard").OnClientEvent:Connect(renderBoard)

-- ---------- toasts ----------

local toastArea = Instance.new("Frame")
toastArea.AnchorPoint = Vector2.new(0.5, 0)
toastArea.Position = UDim2.new(0.5, 0, 0, 70)
toastArea.Size = UDim2.new(0, 420, 0, 120)
toastArea.BackgroundTransparency = 1
toastArea.Parent = gui
list(toastArea, false, 4).HorizontalAlignment = Enum.HorizontalAlignment.Center

local toastCount = 0
Remotes.get("Toast").OnClientEvent:Connect(function(text: string)
	toastCount += 1
	local toast = Instance.new("TextLabel")
	toast.LayoutOrder = toastCount
	toast.BackgroundColor3 = INK
	toast.BackgroundTransparency = 0.15
	toast.TextColor3 = Color3.fromRGB(255, 244, 222)
	toast.Font = Enum.Font.GothamBold
	toast.TextSize = 16
	toast.Text = "  " .. text .. "  "
	toast.AutomaticSize = Enum.AutomaticSize.XY
	toast.Parent = toastArea
	round(toast, 8)
	task.delay(3, function()
		TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.delay(0.5, function()
			toast:Destroy()
		end)
	end)
end)

-- ---------- conversation (slim bar at the bottom) ----------
-- The customer's lines appear in a speech bubble above their head (server-side
-- BillboardGui), so the middle of the screen stays on the NPC and the cafe.
-- This bar only carries the visible cue, your last line, and the input.

local bottom = Instance.new("Frame")
bottom.Name = "Bottom"
bottom.AnchorPoint = Vector2.new(0.5, 1)
bottom.Position = UDim2.new(0.5, 0, 1, -12)
bottom.Size = UDim2.new(0, 700, 0, 0)
bottom.AutomaticSize = Enum.AutomaticSize.Y
bottom.BackgroundTransparency = 1
bottom.Visible = false
bottom.Parent = gui
list(bottom, false, 6).HorizontalAlignment = Enum.HorizontalAlignment.Center

local strip = panel(bottom, "Strip", INK)
strip.BackgroundTransparency = 0.25
strip.Size = UDim2.new(1, 0, 0, 0)
strip.AutomaticSize = Enum.AutomaticSize.Y
strip.LayoutOrder = 1
pad(strip, 8)
list(strip, false, 2)

local customerTitle = para(strip, "", 14, PAPER, false, 1)
customerTitle.Name = "CustomerTitle"
customerTitle.RichText = true
local lastSaid = para(strip, "", 13, Color3.fromRGB(190, 205, 240), false, 2)
lastSaid.Name = "LastSaid"
lastSaid.Visible = false
local typing = para(strip, "", 13, GOLD, false, 3)
typing.Name = "Typing"
typing.Visible = false
stockLine = para(strip, "", 11, Color3.fromRGB(170, 160, 145), false, 4)

-- empty rows collapse so the bar stays one or two lines tall
local function setLine(line: TextLabel, text: string)
	line.Text = text
	line.Visible = text ~= ""
end

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"))
end

local chatRow = Instance.new("Frame")
chatRow.Name = "ChatRow"
chatRow.Size = UDim2.new(1, 0, 0, 40)
chatRow.BackgroundTransparency = 1
chatRow.LayoutOrder = 2
chatRow.Parent = bottom
list(chatRow, true, 8)

local chatBox = Instance.new("TextBox")
chatBox.Name = "ChatBox"
chatBox.Size = UDim2.new(1, -196, 1, 0)
chatBox.BackgroundColor3 = PAPER_DIM
chatBox.Font = Enum.Font.Gotham
chatBox.TextSize = 16
chatBox.TextColor3 = INK
chatBox.PlaceholderText = "Talk to your customer..."
chatBox.Text = ""
chatBox.ClearTextOnFocus = false
chatBox.LayoutOrder = 1
chatBox.Parent = chatRow
round(chatBox, 10)
pad(chatBox, 6)

local sendButton = button(chatRow, "ReplyButton", "Reply", INK, PAPER, 2)
sendButton.Size = UDim2.new(0, 90, 1, 0)
local hintButton = button(chatRow, "CoachButton", "Coach", COACH, Color3.fromRGB(255, 255, 255), 3)
hintButton.Size = UDim2.new(0, 90, 1, 0)

local hasCustomer = false
local function sendChat()
	local text = chatBox.Text
	if #text:gsub("%s", "") == 0 or not hasCustomer then
		return
	end
	chatBox.Text = ""
	Remotes.get("Say"):FireServer(text)
end
sendButton.Activated:Connect(sendChat)
chatBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		sendChat()
	end
end)
hintButton.Activated:Connect(function()
	if hasCustomer then
		Remotes.get("RequestHint"):FireServer()
	end
end)

Remotes.get("Customer").OnClientEvent:Connect(function(visible)
	setLine(lastSaid, "")
	setLine(typing, "")
	if visible then
		hasCustomer = true
		local article = if string.find("aeiou", string.sub(visible.ageGroup, 1, 1), 1, true) then "an" else "a"
		customerTitle.Text = string.format(
			'<font color="#E2AC34"><b>%s</b></font>  ·  %s %s customer, %s.',
			escape(visible.name),
			article,
			visible.ageGroup,
			escape(visible.situation)
		)
	else
		hasCustomer = false
		customerTitle.Text = "Next customer coming..."
	end
end)

Remotes.get("Dialogue").OnClientEvent:Connect(function(speaker: string, text: string, kind: string?)
	if kind == "player" then
		setLine(lastSaid, "You: " .. text)
	end
end)

Remotes.get("Busy").OnClientEvent:Connect(function(busy: boolean, who: string?)
	setLine(typing, if busy then (who or "They") .. " is thinking..." else "")
end)

-- ---------- coach bubble ----------

local coachBubble = panel(gui, "CoachBubble", COACH)
coachBubble.AnchorPoint = Vector2.new(1, 0)
coachBubble.Position = UDim2.new(1, -16, 0, 110)
coachBubble.Size = UDim2.new(0, 280, 0, 0)
coachBubble.AutomaticSize = Enum.AutomaticSize.Y
coachBubble.Visible = false
pad(coachBubble, 12)
list(coachBubble, false, 4)
label(coachBubble, "COACH", 11, Color3.fromRGB(205, 220, 255), true, 1).AutomaticSize = Enum.AutomaticSize.XY
local coachText = para(coachBubble, "", 15, Color3.fromRGB(255, 255, 255), false, 2)

local coachHideThread: thread? = nil
Remotes.get("CoachHint").OnClientEvent:Connect(function(hint: string)
	coachText.Text = hint
	coachBubble.Visible = true
	if coachHideThread then
		task.cancel(coachHideThread)
	end
	coachHideThread = task.delay(10, function()
		coachBubble.Visible = false
	end)
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
	pad(content, 24)
	list(content, false, 10)
	return content
end

-- Lobby
local lobbyOverlay = makeOverlay("LobbyOverlay")
local lobbyCard = card(lobbyOverlay, "LobbyCard", 580, false)
para(lobbyCard, "KIDSIM — ISAAC SIM FOR CHILDREN", 12, ACCENT, true, 1)
local lobbyTitle = para(lobbyCard, "", 32, INK, true, 2)
local lobbyThesis = para(lobbyCard, "", 18, SOFT, true, 3)
local lobbyBriefing = para(lobbyCard, "", 16, INK, false, 4)
local lobbyMenu = para(lobbyCard, "", 14, SOFT, false, 5)
local lobbyLane = para(lobbyCard, "", 14, ACCENT, true, 6)
local startButton = button(lobbyCard, "StartButton", "Start the round", ACCENT, Color3.fromRGB(255, 255, 255), 7)
startButton.Size = UDim2.new(1, 0, 0, 46)
startButton.Activated:Connect(function()
	Remotes.get("StartRound"):FireServer()
end)

-- Waiting banner (joined mid-round or all counters full)
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
local debriefCard = card(debriefOverlay, "DebriefCard", 660, true)

local function setZ(container: Instance)
	for _, d in container:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 6
		end
	end
end
setZ(lobbyCard)

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
	local boardRows = payload.leaderboard or {}
	if payload.rank then
		line(string.format("You placed #%d of %d", payload.rank, #boardRows), 30, INK, true)
	else
		line("This round's results", 30, INK, true)
	end

	line("LEADERBOARD", 12, MUTED, true)
	for rank, row in boardRows do
		local mine = row.userId == player.UserId
		local l = line(
			string.format("%d. %-14s %6s   %s   %d served   %d pts", rank, row.name, money(row.revenue), stars(row.avgStars), row.served, row.score),
			16,
			if mine then ACCENT else INK,
			mine
		)
		l.Font = Enum.Font.Code
	end

	local stats = payload.stats
	if stats then
		line("YOUR COUNTER", 12, MUTED, true)
		local capture = if stats.walletSeen > 0 then math.floor(stats.revenue / stats.walletSeen * 100 + 0.5) else 0
		line(string.format("You earned %s of the %s your customers had in their wallets (%d%%).", money(stats.revenue), money(stats.walletSeen), capture), 18, INK, true)
		line(string.format("Average happiness %s  ·  score %d = revenue + happiness bonus", stars(stats.avgStars), stats.score), 15, SOFT, false)

		for _, r in (payload.records or {}) do
			local bought = {}
			for key, qty in r.items do
				table.insert(bought, tostring(qty) .. " " .. (menuLabels[key] or key))
			end
			local what = if #bought > 0 then table.concat(bought, ", ") else "nothing"
			local starText = string.rep("★", r.stars) .. string.rep("☆", 5 - r.stars)
			line(
				string.format("%s (%s, had %s) — bought %s for %s   %s", r.customer, r.ageGroup, money(r.wallet), what, money(r.paid), starText),
				14,
				if r.stars >= 4 then GOOD elseif r.stars <= 2 then BAD else INK,
				false
			)
		end

		local evaluation = payload.evaluation or {}
		line("SKILLS YOU PRACTICED", 12, MUTED, true)
		for _, skill in (evaluation.skills or {}) do
			line("● " .. (skill.name or skill.tag or "?"), 18, INK, true)
			local evidence = line(skill.evidence or "", 15, SOFT, false)
			local indent = Instance.new("UIPadding")
			indent.PaddingLeft = UDim.new(0, 18)
			indent.Parent = evidence
		end
		if evaluation.wentWell and #evaluation.wentWell > 0 then
			line("WHAT WENT WELL", 12, GOOD, true)
			for _, item in evaluation.wentWell do
				line("+ " .. item, 15, INK, false)
			end
		end
		if evaluation.wentWrong and #evaluation.wentWrong > 0 then
			line("WHAT TO WATCH", 12, BAD, true)
			for _, item in evaluation.wentWrong do
				line("– " .. item, 15, INK, false)
			end
		end
		line("IN THE REAL WORLD", 12, MUTED, true)
		line(evaluation.realWorldTransfer or "", 19, INK, true)
		line("NEXT DRILL", 12, MUTED, true)
		line(evaluation.nextDrill or "", 17, INK, false)
		line(payload.thesis or "", 14, ACCENT, true)
	end

	local again = button(debriefCard, "AgainButton", "Back to the lobby", INK, PAPER, nextOrder())
	again.Size = UDim2.new(1, 0, 0, 44)
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
		timeValue.Text = string.format("%d:%02d", seconds // 60, seconds % 60)
		timeValue.TextColor3 = if seconds <= 20 then BAD else INK
	end
end)

-- ---------- camera ----------
-- During a round the camera is fixed per lane, looking over the counter at
-- the customer, so the player's own avatar never blocks the conversation.

local function setCamera(cf: CFrame?)
	local cam = workspace.CurrentCamera
	if cf then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = cf
		cam.FieldOfView = 60
	else
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = 70
	end
end

-- ---------- phase routing ----------

local function hideAll()
	lobbyOverlay.Visible = false
	bigOverlay.Visible = false
	debriefOverlay.Visible = false
	waitingBanner.Visible = false
	bottom.Visible = false
	coachBubble.Visible = false
	hud.Visible = false
end

local function applyLobby(payload)
	for _, item in (payload.menu or {}) do
		menuLabels[item.key] = item.label
	end
	lobbyTitle.Text = payload.title or ""
	lobbyThesis.Text = "“" .. (payload.thesis or "") .. "”"
	lobbyBriefing.Text = payload.briefing or ""
	local menuBits = {}
	for _, item in (payload.menu or {}) do
		table.insert(menuBits, item.label .. " " .. money(item.price))
	end
	lobbyMenu.Text = "Menu: " .. table.concat(menuBits, " · ") .. string.format("   ·   Round: %d min", (payload.roundSeconds or 180) // 60)
	if payload.lane then
		lobbyLane.Text = string.format("Your counter: #%d. Anyone can start the round for everyone.", payload.lane)
		startButton.Visible = true
	else
		lobbyLane.Text = "All counters are taken — you're watching this time."
		startButton.Visible = false
	end
end

Remotes.get("Phase").OnClientEvent:Connect(function(phase: string, payload)
	if phase == "lobby" then
		hideAll()
		setCamera(nil)
		applyLobby(payload)
		lobbyOverlay.Visible = true
	elseif phase == "waiting" then
		setCamera(nil)
		applyLobby(payload)
		lobbyOverlay.Visible = false
		bottom.Visible = false
		hud.Visible = false
		waitingText.Text = if payload.lanesFull
			then "All counters are taken — watching the leaderboard."
			else "A round is in progress. You'll get a counter next round!"
		waitingBanner.Visible = not debriefOverlay.Visible
	elseif phase == "countdown" then
		hideAll()
		setCamera(payload.camera)
		hud.Visible = true
		revenueValue.Text, starsValue.Text, scoreValue.Text = "$0", "–", "0"
		bigText.Text = "Get ready..."
		bigText.TextSize = 72
		bigOverlay.Visible = true
	elseif phase == "running" then
		hideAll()
		setCamera(payload.camera)
		hud.Visible = true
		bottom.Visible = true
		hasCustomer = false
		customerTitle.Text = "Next customer coming..."
		setLine(lastSaid, "")
	elseif phase == "closing" then
		bottom.Visible = false
		coachBubble.Visible = false
		hasCustomer = false
		bigText.Text = "Time's up!\nYour coach is writing your debrief."
		bigText.TextSize = 30
		bigOverlay.Visible = true
	end
end)
