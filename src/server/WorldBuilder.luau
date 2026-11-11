--!strict
-- Builds the whole playable space from code (no manual Studio editing):
-- one long cafe with N counter lanes side by side, so friends can see each
-- other's counters and live scores. Exposes per-lane hooks the LaneEngine
-- calls (spawnCustomer / despawnCustomer / setSign) and a global setOpen.
-- Visuals are deliberately simple blocks — the demo is the loop, not the map.

local TweenService = game:GetService("TweenService")

local Types = require(game.ReplicatedStorage.Shared.Types)
type Pack = Types.Pack
type CustomerProfile = Types.CustomerProfile

local WorldBuilder = {}

local LOOK_COLORS: { [string]: Color3 } = {
	yellow = Color3.fromRGB(240, 200, 80),
	red = Color3.fromRGB(220, 90, 80),
	purple = Color3.fromRGB(170, 120, 220),
	blue = Color3.fromRGB(90, 140, 230),
	green = Color3.fromRGB(110, 190, 110),
	orange = Color3.fromRGB(240, 150, 70),
	pink = Color3.fromRGB(240, 140, 180),
	teal = Color3.fromRGB(70, 180, 170),
}

local LANE_SPACING = 16
local COUNTER_Z = 3
local CUSTOMER_Z = 6 -- where customers stand, in front of the counter
local DOOR_Z = 26 -- where customers appear
local BEHIND_Z = -3 -- where the shopkeeper stands

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

local function textLabel(parent: Instance, text: string, font: Enum.Font, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = parent
	return label
end

local function menuBoardText(pack: Pack): string
	local lines = { string.upper(pack.title), "----------------------" }
	for _, item in pack.menu do
		local dots = string.rep(".", math.max(2, 16 - #item.label))
		table.insert(lines, string.format("%s %s $%d", item.label, dots, item.price))
	end
	return table.concat(lines, "\n")
end

function WorldBuilder.build(pack: Pack, laneCount: number)
	local folder = Instance.new("Folder")
	folder.Name = "KidSimWorld"
	folder.Parent = workspace

	local halfWidth = laneCount * LANE_SPACING / 2 + 4

	-- floor, walls
	part({
		Name = "Floor",
		Size = Vector3.new(halfWidth * 2, 1, 60),
		Position = Vector3.new(0, 0, 10),
		Color = Color3.fromRGB(225, 214, 196),
		Material = Enum.Material.WoodPlanks,
		Parent = folder,
	})
	part({
		Name = "BackWall",
		Size = Vector3.new(halfWidth * 2, 14, 1),
		Position = Vector3.new(0, 7, -19.5),
		Color = Color3.fromRGB(188, 142, 102),
		Material = Enum.Material.Brick,
		Parent = folder,
	})
	for _, side in { -1, 1 } do
		part({
			Name = if side < 0 then "LeftWall" else "RightWall",
			Size = Vector3.new(1, 14, 60),
			Position = Vector3.new(side * (halfWidth + 0.5), 7, 10),
			Color = Color3.fromRGB(205, 170, 135),
			Material = Enum.Material.Brick,
			Parent = folder,
		})
	end

	-- one shared menu board
	local board = part({
		Name = "MenuBoard",
		Size = Vector3.new(14, 8, 0.4),
		Position = Vector3.new(0, 8.5, -19),
		Color = Color3.fromRGB(40, 44, 42),
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	local boardGui = Instance.new("SurfaceGui")
	boardGui.Face = Enum.NormalId.Back -- +Z face, toward the counters
	boardGui.CanvasSize = Vector2.new(520, 300)
	boardGui.Parent = board
	textLabel(boardGui, menuBoardText(pack), Enum.Font.Code, 28, Color3.fromRGB(240, 235, 210))

	-- open/closed sign over the door
	local sign = part({
		Name = "OpenSign",
		Size = Vector3.new(8, 2.4, 0.4),
		Position = Vector3.new(0, 12, DOOR_Z),
		Color = Color3.fromRGB(200, 70, 70),
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front -- -Z face, toward the inside
	signGui.CanvasSize = Vector2.new(400, 120)
	signGui.Parent = sign
	local signLabel = textLabel(signGui, "CLOSED", Enum.Font.GothamBlack, 64, Color3.fromRGB(255, 255, 255))

	-- fallback spawn in the middle; RoundManager teleports players to lanes
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Size = Vector3.new(4, 1, 4)
	spawnLocation.Position = Vector3.new(0, 0.5, BEHIND_Z - 6)
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Transparency = 1
	spawnLocation.CanCollide = false
	spawnLocation.Duration = 0
	spawnLocation.Parent = folder

	local lanes = {}
	for index = 1, laneCount do
		local x = (index - (laneCount + 1) / 2) * LANE_SPACING
		local laneFolder = Instance.new("Folder")
		laneFolder.Name = "Lane" .. index
		laneFolder.Parent = folder

		part({
			Name = "Counter",
			Size = Vector3.new(11, 3.6, 2.5),
			Position = Vector3.new(x, 1.8, COUNTER_Z),
			Color = Color3.fromRGB(110, 76, 48),
			Material = Enum.Material.Wood,
			Parent = laneFolder,
		})
		part({
			Name = "Till",
			Size = Vector3.new(2, 1.6, 1.4),
			Position = Vector3.new(x + 3.5, 4.4, COUNTER_Z),
			Color = Color3.fromRGB(60, 60, 66),
			Material = Enum.Material.Metal,
			Parent = laneFolder,
		})
		part({
			Name = "PastryCase",
			Size = Vector3.new(4, 1.4, 1.8),
			Position = Vector3.new(x - 3, 4.3, COUNTER_Z),
			Color = Color3.fromRGB(235, 235, 240),
			Material = Enum.Material.Glass,
			Transparency = 0.45,
			Parent = laneFolder,
		})
		-- low divider between this lane and the next ("rails")
		if index < laneCount then
			part({
				Name = "Divider",
				Size = Vector3.new(0.6, 4, 16),
				Position = Vector3.new(x + LANE_SPACING / 2, 2, 1),
				Color = Color3.fromRGB(150, 110, 80),
				Material = Enum.Material.Wood,
				Parent = laneFolder,
			})
		end

		-- floating lane sign: owner + live score, readable from every lane
		local anchor = part({
			Name = "SignAnchor",
			Size = Vector3.new(1, 1, 1),
			Position = Vector3.new(x, 9, COUNTER_Z),
			Transparency = 1,
			CanCollide = false,
			Parent = laneFolder,
		})
		local laneGui = Instance.new("BillboardGui")
		laneGui.Size = UDim2.fromOffset(240, 64)
		laneGui.MaxDistance = 200
		laneGui.Parent = anchor
		local laneTitle = textLabel(laneGui, "Counter " .. index, Enum.Font.GothamBlack, 24, Color3.fromRGB(255, 255, 255))
		laneTitle.Size = UDim2.new(1, 0, 0.55, 0)
		local laneSub = textLabel(laneGui, "open", Enum.Font.GothamBold, 18, Color3.fromRGB(255, 230, 170))
		laneSub.Size = UDim2.new(1, 0, 0.45, 0)
		laneSub.Position = UDim2.fromScale(0, 0.55)

		local counterFront = Vector3.new(x, 3, CUSTOMER_Z)
		local doorPos = Vector3.new(x, 3, DOOR_Z)
		local currentNpc: Model? = nil

		local function despawnCustomer()
			local npc = currentNpc
			currentNpc = nil
			if not npc then
				return
			end
			local body = npc:FindFirstChild("Body") :: Part?
			local head = npc:FindFirstChild("Head") :: Part?
			if body and head then
				local walkInfo = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
				TweenService:Create(body, walkInfo, { Position = doorPos }):Play()
				TweenService:Create(head, walkInfo, { Position = doorPos + Vector3.new(0, 2.3, 0) }):Play()
			end
			task.delay(1.3, function()
				npc:Destroy()
			end)
		end

		local function spawnCustomer(profile: CustomerProfile)
			if currentNpc then
				currentNpc:Destroy()
				currentNpc = nil
			end
			local color = LOOK_COLORS[profile.look] or Color3.fromRGB(180, 180, 180)
			-- kids are a bit shorter
			local height = if profile.ageGroup == "kid" then 2.2 else 3

			local npc = Instance.new("Model")
			npc.Name = profile.name
			local body = part({
				Name = "Body",
				Size = Vector3.new(2, height, 1.2),
				Position = doorPos,
				Color = color,
				Material = Enum.Material.SmoothPlastic,
				Parent = npc,
			})
			local headOffset = Vector3.new(0, height / 2 + 0.8, 0)
			local head = part({
				Name = "Head",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1.6, 1.6, 1.6),
				Position = doorPos + headOffset,
				Color = Color3.fromRGB(245, 215, 180),
				Material = Enum.Material.SmoothPlastic,
				Parent = npc,
			})
			local face = Instance.new("Decal")
			face.Texture = "rbxasset://textures/face.png"
			face.Face = Enum.NormalId.Front
			face.Parent = head

			local nameGui = Instance.new("BillboardGui")
			nameGui.Size = UDim2.fromOffset(160, 32)
			nameGui.StudsOffset = Vector3.new(0, 1.5, 0)
			nameGui.MaxDistance = 60
			nameGui.Parent = head
			textLabel(nameGui, profile.name, Enum.Font.GothamBold, 18, Color3.fromRGB(255, 255, 255))

			npc.PrimaryPart = body
			npc.Parent = laneFolder
			currentNpc = npc

			local walkInfo = TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			TweenService:Create(body, walkInfo, { Position = counterFront - Vector3.new(0, (3 - height) / 2, 0) }):Play()
			TweenService:Create(head, walkInfo, { Position = counterFront - Vector3.new(0, (3 - height) / 2, 0) + headOffset }):Play()
		end

		local function setSign(title: string, subtitle: string)
			laneTitle.Text = title
			laneSub.Text = subtitle
		end

		lanes[index] = {
			spawnCustomer = spawnCustomer,
			despawnCustomer = despawnCustomer,
			setSign = setSign,
			spawnCFrame = CFrame.lookAt(Vector3.new(x, 3, BEHIND_Z), Vector3.new(x, 3, CUSTOMER_Z + 10)),
		}
	end

	local function setOpen(open: boolean)
		sign.Color = open and Color3.fromRGB(70, 180, 110) or Color3.fromRGB(200, 70, 70)
		signLabel.Text = open and "OPEN" or "CLOSED"
	end

	return {
		lanes = lanes,
		setOpen = setOpen,
	}
end

return WorldBuilder
