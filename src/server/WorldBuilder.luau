--!strict
-- Builds the whole playable space from code (no manual Studio editing),
-- and exposes the WorldHooks the engine calls: spawnCounterpart /
-- despawnCounterpart / setOpen. Visuals are deliberately simple blocks —
-- the demo is the loop, not the map.

local TweenService = game:GetService("TweenService")

local Types = require(game.ReplicatedStorage.Shared.Types)
type PackEvent = Types.PackEvent

local WorldBuilder = {}

local LOOK_COLORS: { [string]: Color3 } = {
	yellow = Color3.fromRGB(240, 200, 80),
	red = Color3.fromRGB(220, 90, 80),
	purple = Color3.fromRGB(170, 120, 220),
	blue = Color3.fromRGB(90, 140, 230),
	green = Color3.fromRGB(110, 190, 110),
}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

-- Cafe sits around origin. Player spawns behind the counter,
-- customers walk in from the door to the counter.
local COUNTER_FRONT = Vector3.new(0, 3, 6) -- where customers stand
local DOOR_POS = Vector3.new(0, 3, 26) -- where customers appear

function WorldBuilder.build(menuText: string?)
	local folder = Instance.new("Folder")
	folder.Name = "KidSimWorld"
	folder.Parent = workspace

	-- floor
	part({
		Name = "Floor",
		Size = Vector3.new(44, 1, 60),
		Position = Vector3.new(0, 0, 10),
		Color = Color3.fromRGB(225, 214, 196),
		Material = Enum.Material.WoodPlanks,
		Parent = folder,
	})

	-- back wall + side walls (low, cozy)
	part({
		Name = "BackWall",
		Size = Vector3.new(44, 14, 1),
		Position = Vector3.new(0, 7, -19.5),
		Color = Color3.fromRGB(188, 142, 102),
		Material = Enum.Material.Brick,
		Parent = folder,
	})
	part({
		Name = "LeftWall",
		Size = Vector3.new(1, 14, 60),
		Position = Vector3.new(-21.5, 7, 10),
		Color = Color3.fromRGB(205, 170, 135),
		Material = Enum.Material.Brick,
		Parent = folder,
	})
	part({
		Name = "RightWall",
		Size = Vector3.new(1, 14, 60),
		Position = Vector3.new(21.5, 7, 10),
		Color = Color3.fromRGB(205, 170, 135),
		Material = Enum.Material.Brick,
		Parent = folder,
	})

	-- counter the player stands behind
	part({
		Name = "Counter",
		Size = Vector3.new(16, 3.6, 2.5),
		Position = Vector3.new(0, 1.8, 3),
		Color = Color3.fromRGB(110, 76, 48),
		Material = Enum.Material.Wood,
		Parent = folder,
	})
	-- till
	local till = part({
		Name = "Till",
		Size = Vector3.new(2, 1.6, 1.4),
		Position = Vector3.new(5, 4.4, 3),
		Color = Color3.fromRGB(60, 60, 66),
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	local tillGui = Instance.new("BillboardGui")
	tillGui.Size = UDim2.fromOffset(80, 28)
	tillGui.StudsOffset = Vector3.new(0, 1.4, 0)
	tillGui.AlwaysOnTop = true
	tillGui.Parent = till
	local tillLabel = Instance.new("TextLabel")
	tillLabel.Size = UDim2.fromScale(1, 1)
	tillLabel.BackgroundTransparency = 1
	tillLabel.Text = "TILL"
	tillLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	tillLabel.TextStrokeTransparency = 0.4
	tillLabel.Font = Enum.Font.GothamBold
	tillLabel.TextSize = 14
	tillLabel.Parent = tillGui

	-- pastry case
	part({
		Name = "PastryCase",
		Size = Vector3.new(5, 1.4, 1.8),
		Position = Vector3.new(-4.5, 4.3, 3),
		Color = Color3.fromRGB(235, 235, 240),
		Material = Enum.Material.Glass,
		Transparency = 0.45,
		Parent = folder,
	})

	-- menu board on the back wall
	local board = part({
		Name = "MenuBoard",
		Size = Vector3.new(12, 7, 0.4),
		Position = Vector3.new(0, 8.5, -19),
		Color = Color3.fromRGB(40, 44, 42),
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(480, 280)
	surface.Parent = board
	local menuLabel = Instance.new("TextLabel")
	menuLabel.Size = UDim2.fromScale(1, 1)
	menuLabel.BackgroundTransparency = 1
	menuLabel.Font = Enum.Font.Code
	menuLabel.TextSize = 34
	menuLabel.TextColor3 = Color3.fromRGB(240, 235, 210)
	menuLabel.Text = menuText or "MENU"
	menuLabel.TextXAlignment = Enum.TextXAlignment.Center
	menuLabel.Parent = surface

	-- open/closed sign over the door area
	local sign = part({
		Name = "OpenSign",
		Size = Vector3.new(8, 2.4, 0.4),
		Position = Vector3.new(0, 12, 26),
		Color = Color3.fromRGB(200, 70, 70),
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Back
	signGui.CanvasSize = Vector2.new(400, 120)
	signGui.Parent = sign
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.BackgroundTransparency = 1
	signLabel.Font = Enum.Font.GothamBlack
	signLabel.TextSize = 64
	signLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	signLabel.Text = "CLOSED"
	signLabel.Parent = signGui

	-- two little tables (the chore in one incident)
	for i, x in { -12, 12 } do
		part({
			Name = "Table" .. tostring(i),
			Size = Vector3.new(4, 3, 4),
			Position = Vector3.new(x, 1.5, 14),
			Color = Color3.fromRGB(140, 100, 64),
			Material = Enum.Material.Wood,
			Parent = folder,
		})
	end

	-- player spawn behind the counter
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Size = Vector3.new(4, 1, 4)
	spawnLocation.Position = Vector3.new(0, 0.5, -3)
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Transparency = 1
	spawnLocation.CanCollide = false
	spawnLocation.Duration = 0
	spawnLocation.Parent = folder

	-- ---------- counterpart NPC ----------

	local currentNpc: Model? = nil

	local function spawnCounterpart(event: PackEvent)
		if currentNpc then
			currentNpc:Destroy()
			currentNpc = nil
		end
		local color = LOOK_COLORS[event.counterpart.look or ""] or Color3.fromRGB(180, 180, 180)

		local npc = Instance.new("Model")
		npc.Name = event.counterpart.name

		local body = part({
			Name = "Body",
			Size = Vector3.new(2, 3, 1.2),
			Position = DOOR_POS,
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			Parent = npc,
		})
		local head = part({
			Name = "Head",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.6, 1.6, 1.6),
			Position = DOOR_POS + Vector3.new(0, 2.3, 0),
			Color = Color3.fromRGB(245, 215, 180),
			Material = Enum.Material.SmoothPlastic,
			Parent = npc,
		})
		local face = Instance.new("Decal")
		face.Texture = "rbxasset://textures/face.png"
		face.Face = Enum.NormalId.Front
		face.Parent = head

		local nameGui = Instance.new("BillboardGui")
		nameGui.Size = UDim2.fromOffset(160, 36)
		nameGui.StudsOffset = Vector3.new(0, 1.6, 0)
		nameGui.AlwaysOnTop = true
		nameGui.Parent = head
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.fromScale(1, 1)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 18
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextStrokeTransparency = 0.3
		nameLabel.Text = event.counterpart.name
		nameLabel.Parent = nameGui

		npc.PrimaryPart = body
		npc.Parent = folder
		currentNpc = npc

		-- walk from door to counter
		local walkInfo = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		TweenService:Create(body, walkInfo, { Position = COUNTER_FRONT }):Play()
		TweenService:Create(head, walkInfo, { Position = COUNTER_FRONT + Vector3.new(0, 2.3, 0) }):Play()
	end

	local function despawnCounterpart()
		local npc = currentNpc
		currentNpc = nil
		if not npc then
			return
		end
		local body = npc:FindFirstChild("Body") :: Part?
		local head = npc:FindFirstChild("Head") :: Part?
		if body and head then
			local walkInfo = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
			TweenService:Create(body, walkInfo, { Position = DOOR_POS }):Play()
			TweenService:Create(head, walkInfo, { Position = DOOR_POS + Vector3.new(0, 2.3, 0) }):Play()
		end
		task.delay(1.5, function()
			npc:Destroy()
		end)
	end

	local function setOpen(open: boolean)
		sign.Color = open and Color3.fromRGB(70, 180, 110) or Color3.fromRGB(200, 70, 70)
		signLabel.Text = open and "OPEN" or "CLOSED"
	end

	return {
		spawnCounterpart = spawnCounterpart,
		despawnCounterpart = despawnCounterpart,
		setOpen = setOpen,
	}
end

return WorldBuilder
