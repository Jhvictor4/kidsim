--!strict
-- All player-facing UI, built from code: HUD meters, dialogue + choices,
-- free-text chat to the counterpart, one-per-incident coach hint, and the
-- full-screen sim-to-real debrief. Pack-agnostic: meter/inventory defs
-- arrive in the Intro phase payload.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- WaitForChild: on a live server the client can run before Shared replicates
local Remotes = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---------- palette ----------
local INK = Color3.fromRGB(34, 32, 29)
local PAPER = Color3.fromRGB(248, 243, 234)
local PAPER_DIM = Color3.fromRGB(236, 229, 216)
local ACCENT = Color3.fromRGB(214, 124, 48)
local GOOD = Color3.fromRGB(62, 142, 94)
local BAD = Color3.fromRGB(186, 70, 60)
local COACH = Color3.fromRGB(78, 112, 180)

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

local function label(parent: Instance, text: string, size: number, color: Color3?, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextSize = size
	l.TextColor3 = color or INK
	l.Text = text
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, bg: Color3, fg: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.TextColor3 = fg
	b.BackgroundColor3 = bg
	b.AutoButtonColor = true
	b.Text = text
	b.Parent = parent
	round(b, 10)
	return b
end

-- ---------- root ----------

local gui = Instance.new("ScreenGui")
gui.Name = "KidSimUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- ---------- HUD (top) ----------

local hud = Instance.new("Frame")
hud.Name = "HUD"
hud.AnchorPoint = Vector2.new(0.5, 0)
hud.Position = UDim2.new(0.5, 0, 0, 12)
hud.Size = UDim2.new(0, 0, 0, 44)
hud.AutomaticSize = Enum.AutomaticSize.X
hud.BackgroundColor3 = PAPER
hud.BackgroundTransparency = 0.05
hud.Visible = false
hud.Parent = gui
round(hud, 12)
pad(hud, 8)
local hudLayout = Instance.new("UIListLayout")
hudLayout.FillDirection = Enum.FillDirection.Horizontal
hudLayout.Padding = UDim.new(0, 14)
hudLayout.VerticalAlignment = Enum.VerticalAlignment.Center
hudLayout.Parent = hud

type MeterDef = { key: string, label: string, format: string, max: number? }
local meterDefs: { MeterDef } = {}
local inventoryLabels: { [string]: string } = {}
local meterValueLabels: { [string]: TextLabel } = {}
local inventoryLabel: TextLabel? = nil

local function formatMeter(def: MeterDef, value: number): string
	if def.format == "currency" then
		return "$" .. tostring(value)
	elseif def.format == "score" then
		return tostring(value) .. (def.max and ("/" .. tostring(def.max)) or "")
	end
	return tostring(value)
end

local function buildHud()
	for _, child in hud:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	meterValueLabels = {}
	for _, def in meterDefs do
		local chip = Instance.new("Frame")
		chip.BackgroundTransparency = 1
		chip.AutomaticSize = Enum.AutomaticSize.XY
		chip.Parent = hud
		local chipLayout = Instance.new("UIListLayout")
		chipLayout.FillDirection = Enum.FillDirection.Vertical
		chipLayout.Parent = chip
		local title = label(chip, string.upper(def.label), 11, Color3.fromRGB(130, 122, 110), true)
		title.AutomaticSize = Enum.AutomaticSize.XY
		local value = label(chip, "-", 20, INK, true)
		value.AutomaticSize = Enum.AutomaticSize.XY
		meterValueLabels[def.key] = value
	end
	-- inventory chip
	local invChip = Instance.new("Frame")
	invChip.BackgroundTransparency = 1
	invChip.AutomaticSize = Enum.AutomaticSize.XY
	invChip.Parent = hud
	local invLayout = Instance.new("UIListLayout")
	invLayout.FillDirection = Enum.FillDirection.Vertical
	invLayout.Parent = invChip
	local invTitle = label(invChip, "STOCK", 11, Color3.fromRGB(130, 122, 110), true)
	invTitle.AutomaticSize = Enum.AutomaticSize.XY
	local invValue = label(invChip, "-", 15, INK, true)
	invValue.AutomaticSize = Enum.AutomaticSize.XY
	inventoryLabel = invValue
	hud.Visible = true
end

Remotes.get("State").OnClientEvent:Connect(function(state)
	for key, valueLabel in meterValueLabels do
		local value = state.meters[key]
		if value ~= nil then
			for _, def in meterDefs do
				if def.key == key then
					valueLabel.Text = formatMeter(def, value)
				end
			end
		end
	end
	if inventoryLabel then
		local bits = {}
		for key, count in state.inventory do
			table.insert(bits, (inventoryLabels[key] or key) .. " " .. tostring(count))
		end
		table.sort(bits)
		inventoryLabel.Text = table.concat(bits, "   ")
	end
end)

-- ---------- toasts ----------

local toastArea = Instance.new("Frame")
toastArea.AnchorPoint = Vector2.new(0.5, 0)
toastArea.Position = UDim2.new(0.5, 0, 0, 64)
toastArea.Size = UDim2.new(0, 400, 0, 120)
toastArea.BackgroundTransparency = 1
toastArea.Parent = gui
local toastLayout = Instance.new("UIListLayout")
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Padding = UDim.new(0, 4)
toastLayout.Parent = toastArea

Remotes.get("Toast").OnClientEvent:Connect(function(text: string)
	local toast = Instance.new("TextLabel")
	toast.BackgroundColor3 = INK
	toast.BackgroundTransparency = 0.15
	toast.TextColor3 = Color3.fromRGB(255, 244, 222)
	toast.Font = Enum.Font.GothamBold
	toast.TextSize = 15
	toast.Text = "  " .. text .. "  "
	toast.AutomaticSize = Enum.AutomaticSize.XY
	toast.Parent = toastArea
	round(toast, 8)
	task.delay(2.6, function()
		TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.delay(0.5, function()
			toast:Destroy()
		end)
	end)
end)

-- ---------- dialogue + choices + chat (bottom) ----------

local bottom = Instance.new("Frame")
bottom.AnchorPoint = Vector2.new(0.5, 1)
bottom.Position = UDim2.new(0.5, 0, 1, -16)
bottom.Size = UDim2.new(0, 620, 0, 0)
bottom.AutomaticSize = Enum.AutomaticSize.Y
bottom.BackgroundTransparency = 1
bottom.Visible = false
bottom.Parent = gui
local bottomLayout = Instance.new("UIListLayout")
bottomLayout.FillDirection = Enum.FillDirection.Vertical
bottomLayout.Padding = UDim.new(0, 8)
bottomLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
bottomLayout.Parent = bottom

-- choices
local choicesFrame = Instance.new("Frame")
choicesFrame.Size = UDim2.new(1, 0, 0, 0)
choicesFrame.AutomaticSize = Enum.AutomaticSize.Y
choicesFrame.BackgroundTransparency = 1
choicesFrame.LayoutOrder = 1
choicesFrame.Parent = bottom
local choicesLayout = Instance.new("UIListLayout")
choicesLayout.FillDirection = Enum.FillDirection.Vertical
choicesLayout.Padding = UDim.new(0, 6)
choicesLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
choicesLayout.Parent = choicesFrame

-- dialogue panel
local dialogue = Instance.new("Frame")
dialogue.Size = UDim2.new(1, 0, 0, 0)
dialogue.AutomaticSize = Enum.AutomaticSize.Y
dialogue.BackgroundColor3 = PAPER
dialogue.BackgroundTransparency = 0.04
dialogue.LayoutOrder = 2
dialogue.Parent = bottom
round(dialogue, 14)
pad(dialogue, 14)
local dialogueLayout = Instance.new("UIListLayout")
dialogueLayout.FillDirection = Enum.FillDirection.Vertical
dialogueLayout.Padding = UDim.new(0, 4)
dialogueLayout.Parent = dialogue

local speakerLabel = label(dialogue, "", 13, ACCENT, true)
speakerLabel.Size = UDim2.new(1, 0, 0, 16)
local textLabel = label(dialogue, "", 18, INK)
textLabel.Size = UDim2.new(1, 0, 0, 0)
textLabel.AutomaticSize = Enum.AutomaticSize.Y

-- chat row
local chatRow = Instance.new("Frame")
chatRow.Size = UDim2.new(1, 0, 0, 40)
chatRow.BackgroundTransparency = 1
chatRow.LayoutOrder = 3
chatRow.Parent = bottom
local chatLayout = Instance.new("UIListLayout")
chatLayout.FillDirection = Enum.FillDirection.Horizontal
chatLayout.Padding = UDim.new(0, 8)
chatLayout.Parent = chatRow

local chatBox = Instance.new("TextBox")
chatBox.Size = UDim2.new(1, -196, 1, 0)
chatBox.BackgroundColor3 = PAPER_DIM
chatBox.Font = Enum.Font.Gotham
chatBox.TextSize = 16
chatBox.TextColor3 = INK
chatBox.PlaceholderText = "Say something to them..."
chatBox.Text = ""
chatBox.ClearTextOnFocus = false
chatBox.Parent = chatRow
round(chatBox, 10)
pad(chatBox, 6)

local sendButton = button(chatRow, "Reply", INK, PAPER)
sendButton.Size = UDim2.new(0, 90, 1, 0)

local hintButton = button(chatRow, "Coach", COACH, Color3.fromRGB(255, 255, 255))
hintButton.Size = UDim2.new(0, 90, 1, 0)

local function sendChat()
	local text = chatBox.Text
	if #text:gsub("%s", "") == 0 then
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
	Remotes.get("RequestHint"):FireServer()
end)

Remotes.get("Dialogue").OnClientEvent:Connect(function(speaker: string, text: string, kind: string?)
	speakerLabel.Text = speaker
	speakerLabel.TextColor3 = kind == "player" and COACH or ACCENT
	textLabel.Text = text
end)

Remotes.get("Choices").OnClientEvent:Connect(function(choices)
	for _, child in choicesFrame:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for _, choice in choices do
		local b = button(choicesFrame, choice.label, Color3.fromRGB(255, 252, 245), INK)
		b.Size = UDim2.new(1, 0, 0, 38)
		b.TextSize = 15
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(205, 192, 170)
		stroke.Thickness = 1
		stroke.Parent = b
		b.Activated:Connect(function()
			Remotes.get("Choose"):FireServer(choice.id)
		end)
	end
end)

-- busy ("...") indicator
Remotes.get("Busy").OnClientEvent:Connect(function(busy: boolean)
	if busy then
		speakerLabel.Text = speakerLabel.Text:gsub(" •••$", "") .. " •••"
	else
		speakerLabel.Text = speakerLabel.Text:gsub(" •••$", "")
	end
end)

-- ---------- coach bubble ----------

local coachBubble = Instance.new("Frame")
coachBubble.AnchorPoint = Vector2.new(1, 0)
coachBubble.Position = UDim2.new(1, -16, 0, 80)
coachBubble.Size = UDim2.new(0, 300, 0, 0)
coachBubble.AutomaticSize = Enum.AutomaticSize.Y
coachBubble.BackgroundColor3 = COACH
coachBubble.Visible = false
coachBubble.Parent = gui
round(coachBubble, 12)
pad(coachBubble, 12)
local coachLayout = Instance.new("UIListLayout")
coachLayout.FillDirection = Enum.FillDirection.Vertical
coachLayout.Padding = UDim.new(0, 4)
coachLayout.Parent = coachBubble
local coachTitle = label(coachBubble, "COACH", 11, Color3.fromRGB(205, 220, 255), true)
coachTitle.AutomaticSize = Enum.AutomaticSize.XY
local coachText = label(coachBubble, "", 15, Color3.fromRGB(255, 255, 255))
coachText.Size = UDim2.new(1, 0, 0, 0)
coachText.AutomaticSize = Enum.AutomaticSize.Y

local coachHideThread: thread? = nil
Remotes.get("CoachHint").OnClientEvent:Connect(function(hint: string)
	coachText.Text = hint
	coachBubble.Visible = true
	if coachHideThread then
		task.cancel(coachHideThread)
	end
	coachHideThread = task.delay(8, function()
		coachBubble.Visible = false
	end)
end)

-- ---------- overlays ----------

local function makeOverlay(): Frame
	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(24, 22, 20)
	overlay.BackgroundTransparency = 0.12
	overlay.Visible = false
	overlay.ZIndex = 5
	overlay.Parent = gui
	return overlay
end

-- Intro
local introOverlay = makeOverlay()
local introCard = Instance.new("Frame")
introCard.AnchorPoint = Vector2.new(0.5, 0.5)
introCard.Position = UDim2.fromScale(0.5, 0.5)
introCard.Size = UDim2.new(0, 560, 0, 0)
introCard.AutomaticSize = Enum.AutomaticSize.Y
introCard.BackgroundColor3 = PAPER
introCard.ZIndex = 6
introCard.Parent = introOverlay
round(introCard, 16)
pad(introCard, 24)
local introLayout = Instance.new("UIListLayout")
introLayout.FillDirection = Enum.FillDirection.Vertical
introLayout.Padding = UDim.new(0, 12)
introLayout.Parent = introCard

local introKicker = label(introCard, "KIDSIM — ISAAC SIM FOR CHILDREN", 12, ACCENT, true)
introKicker.ZIndex = 6
introKicker.Size = UDim2.new(1, 0, 0, 14)
local introTitle = label(introCard, "", 32, INK, true)
introTitle.ZIndex = 6
introTitle.Size = UDim2.new(1, 0, 0, 0)
introTitle.AutomaticSize = Enum.AutomaticSize.Y
local introThesis = label(introCard, "", 18, Color3.fromRGB(100, 92, 80), true)
introThesis.ZIndex = 6
introThesis.Size = UDim2.new(1, 0, 0, 0)
introThesis.AutomaticSize = Enum.AutomaticSize.Y
local introBriefing = label(introCard, "", 16, INK)
introBriefing.ZIndex = 6
introBriefing.Size = UDim2.new(1, 0, 0, 0)
introBriefing.AutomaticSize = Enum.AutomaticSize.Y
local startButton = button(introCard, "Start my shift", ACCENT, Color3.fromRGB(255, 255, 255))
startButton.ZIndex = 6
startButton.Size = UDim2.new(1, 0, 0, 46)
startButton.Activated:Connect(function()
	Remotes.get("Continue"):FireServer()
end)

-- Close
local closeOverlay = makeOverlay()
local closeLabel = label(closeOverlay, "Closing up the shop...\nYour coach is writing your debrief.", 24, PAPER, true)
closeLabel.ZIndex = 6
closeLabel.AnchorPoint = Vector2.new(0.5, 0.5)
closeLabel.Position = UDim2.fromScale(0.5, 0.5)
closeLabel.Size = UDim2.new(0, 600, 0, 120)
closeLabel.TextXAlignment = Enum.TextXAlignment.Center

-- Debrief
local debriefOverlay = makeOverlay()
local debriefCard = Instance.new("ScrollingFrame")
debriefCard.AnchorPoint = Vector2.new(0.5, 0.5)
debriefCard.Position = UDim2.fromScale(0.5, 0.5)
debriefCard.Size = UDim2.new(0, 640, 0.86, 0)
debriefCard.BackgroundColor3 = PAPER
debriefCard.ScrollBarThickness = 6
debriefCard.AutomaticCanvasSize = Enum.AutomaticSize.Y
debriefCard.CanvasSize = UDim2.new(0, 0, 0, 0)
debriefCard.ZIndex = 6
debriefCard.Parent = debriefOverlay
round(debriefCard, 16)
pad(debriefCard, 24)
local debriefLayout = Instance.new("UIListLayout")
debriefLayout.FillDirection = Enum.FillDirection.Vertical
debriefLayout.Padding = UDim.new(0, 10)
debriefLayout.Parent = debriefCard

local function clearDebrief()
	for _, child in debriefCard:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function debriefLine(text: string, size: number, color: Color3?, bold: boolean?, order: number): TextLabel
	local l = label(debriefCard, text, size, color, bold)
	l.ZIndex = 6
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.LayoutOrder = order
	return l
end

Remotes.get("Debrief").OnClientEvent:Connect(function(payload)
	clearDebrief()
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	debriefLine("SHIFT DEBRIEF — " .. string.upper(payload.title or ""), 12, ACCENT, true, nextOrder())
	debriefLine("What you just practiced, for real.", 28, INK, true, nextOrder())

	-- meters before -> after
	for _, def in (payload.meters or {}) do
		local before = payload.initialMeters[def.key] or 0
		local after = payload.finalMeters[def.key] or 0
		local delta = after - before
		local arrow = delta > 0 and "▲" or (delta < 0 and "▼" or "—")
		local deltaColor = GOOD
		if def.key == "waste" then
			deltaColor = delta > 0 and BAD or GOOD
		elseif delta < 0 then
			deltaColor = BAD
		end
		local line = debriefLine(
			def.label .. ":  " .. formatMeter(def, before) .. "  →  " .. formatMeter(def, after) .. "   " .. arrow,
			18,
			delta == 0 and INK or deltaColor,
			true,
			nextOrder()
		)
		line.Font = Enum.Font.Code
	end

	local evaluation = payload.evaluation or {}

	debriefLine("SKILLS YOU PRACTICED", 12, Color3.fromRGB(130, 122, 110), true, nextOrder())
	for _, skill in (evaluation.skills or {}) do
		debriefLine("● " .. (skill.name or skill.tag or "?"), 18, INK, true, nextOrder())
		debriefLine("    " .. (skill.evidence or ""), 15, Color3.fromRGB(100, 92, 80), false, nextOrder())
	end

	if evaluation.wentWell and #evaluation.wentWell > 0 then
		debriefLine("WHAT WENT WELL", 12, GOOD, true, nextOrder())
		for _, item in evaluation.wentWell do
			debriefLine("+ " .. item, 15, INK, false, nextOrder())
		end
	end
	if evaluation.wentWrong and #evaluation.wentWrong > 0 then
		debriefLine("WHAT TO WATCH", 12, BAD, true, nextOrder())
		for _, item in evaluation.wentWrong do
			debriefLine("– " .. item, 15, INK, false, nextOrder())
		end
	end

	debriefLine("IN THE REAL WORLD", 12, Color3.fromRGB(130, 122, 110), true, nextOrder())
	debriefLine(evaluation.realWorldTransfer or "", 19, INK, true, nextOrder())

	debriefLine("NEXT DRILL", 12, Color3.fromRGB(130, 122, 110), true, nextOrder())
	debriefLine(evaluation.nextDrill or "", 17, INK, false, nextOrder())

	debriefLine(payload.thesis or "", 14, ACCENT, true, nextOrder())

	local again = button(debriefCard, "Run another shift", INK, PAPER)
	again.ZIndex = 6
	again.Size = UDim2.new(1, 0, 0, 44)
	again.LayoutOrder = nextOrder()
	again.Activated:Connect(function()
		debriefOverlay.Visible = false
		Remotes.get("Continue"):FireServer()
	end)

	closeOverlay.Visible = false
	debriefOverlay.Visible = true
end)

-- ---------- phase routing ----------

Remotes.get("Phase").OnClientEvent:Connect(function(phase: string, payload)
	if phase == "intro" then
		meterDefs = payload.meters or {}
		inventoryLabels = payload.inventoryLabels or {}
		buildHud()
		introTitle.Text = payload.title or ""
		introThesis.Text = "“" .. (payload.thesis or "") .. "”"
		introBriefing.Text = payload.briefing or ""
		debriefOverlay.Visible = false
		closeOverlay.Visible = false
		bottom.Visible = false
		introOverlay.Visible = true
	elseif phase == "shift" then
		introOverlay.Visible = false
		bottom.Visible = true
	elseif phase == "incident" then
		speakerLabel.Text = payload.counterpart or ""
		textLabel.Text = ""
	elseif phase == "close" then
		bottom.Visible = false
		coachBubble.Visible = false
		closeOverlay.Visible = true
	elseif phase == "debrief" then
		-- Debrief remote carries the payload; overlay switch happens there.
	end
end)
