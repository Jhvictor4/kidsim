--!strict
-- Builds the whole playable space from code (no manual Studio editing):
-- one shop per player, side by side. Each shop has a raised throne for the
-- owner, three staff counters, a door customers walk in from, and queue
-- spots in front of the throne where staff wait with questions.
-- Exposes per-counter hooks (staff + customer NPCs, speech bubbles,
-- walking) and per-shop hooks (sign, open/closed, throne seat).
-- Visuals are deliberately simple blocks — the demo is the loop, not the map.

local TweenService = game:GetService("TweenService")

local Types = require(game.ReplicatedStorage.Shared.Types)
type Pack = Types.Pack
type CustomerProfile = Types.CustomerProfile
type StaffProfile = Types.StaffProfile

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
	-- staff uniforms
	white = Color3.fromRGB(235, 235, 230),
	brown = Color3.fromRGB(140, 95, 60),
	navy = Color3.fromRGB(50, 70, 120),
	olive = Color3.fromRGB(120, 130, 70),
}

local SHOP_SPACING = 72
local COUNTER_OFFSETS = { -16, 0, 16 }
local COUNTER_Z = 6
local STAFF_Z = 3.5 -- behind the counter
local CUSTOMER_Z = 9 -- in front of the counter
local DOOR_Z = 32
local THRONE_Z = -15
local QUEUE_Z = -9
local QUEUE_OFFSETS = { -5, 0, 5 }

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

-- A simple blocky person with a name tag and a hidden speech bubble.
-- Not AlwaysOnTop: with it on, bubbles did not render in Studio play.
local function makeNpc(name: string, tag: string, color: Color3, height: number, at: Vector3, parent: Instance): Model
	local npc = Instance.new("Model")
	npc.Name = name
	local body = part({
		Name = "Body",
		Size = Vector3.new(2, height, 1.2),
		Position = at,
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = npc,
	})
	local head = part({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 1.6, 1.6),
		Position = at + Vector3.new(0, height / 2 + 0.8, 0),
		Color = Color3.fromRGB(245, 215, 180),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = npc,
	})
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	local nameGui = Instance.new("BillboardGui")
	nameGui.Name = "NameTag"
	nameGui.Size = UDim2.fromOffset(180, 30)
	nameGui.StudsOffset = Vector3.new(0, 1.5, 0)
	nameGui.MaxDistance = 80
	nameGui.Parent = head
	textLabel(nameGui, if tag ~= "" then name .. "  ·  " .. tag else name, Enum.Font.GothamBold, 16, Color3.fromRGB(255, 255, 255))

	local bubbleGui = Instance.new("BillboardGui")
	bubbleGui.Name = "Bubble"
	bubbleGui.Size = UDim2.fromOffset(220, 140)
	bubbleGui.SizeOffset = Vector2.new(0, 0.5) -- bottom edge sits at the anchor
	bubbleGui.StudsOffset = Vector3.new(0, 2.1, 0)
	bubbleGui.MaxDistance = 80
	bubbleGui.Enabled = false
	bubbleGui.Parent = head
	local bubble = Instance.new("TextLabel")
	bubble.Name = "Text"
	bubble.AnchorPoint = Vector2.new(0.5, 1)
	bubble.Position = UDim2.fromScale(0.5, 1)
	bubble.Size = UDim2.new(1, 0, 0, 0)
	bubble.AutomaticSize = Enum.AutomaticSize.Y
	bubble.BackgroundColor3 = Color3.fromRGB(255, 252, 245)
	bubble.TextColor3 = Color3.fromRGB(34, 32, 29)
	bubble.Font = Enum.Font.Gotham
	bubble.TextSize = 14
	bubble.TextWrapped = true
	bubble.Text = ""
	bubble.Parent = bubbleGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bubble
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = bubble

	npc.PrimaryPart = body
	npc.Parent = parent
	return npc
end

local function npcSay(npc: Model?, text: string?)
	local bubbleGui = npc and npc:FindFirstChild("Bubble", true) :: BillboardGui?
	if not bubbleGui then
		return
	end
	local bubble = bubbleGui:FindFirstChild("Text") :: TextLabel?
	if bubble then
		bubble.Text = text or ""
	end
	bubbleGui.Enabled = text ~= nil and text ~= ""
end

-- Tween body + head so the body's centre ends at `to`.
local function npcWalk(npc: Model?, to: Vector3, seconds: number)
	if not npc then
		return
	end
	local body = npc:FindFirstChild("Body") :: Part?
	local head = npc:FindFirstChild("Head") :: Part?
	if not body or not head then
		return
	end
	local headOffset = head.Position - body.Position
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(body, info, { Position = to }):Play()
	TweenService:Create(head, info, { Position = to + headOffset }):Play()
end

local function headPosition(npc: Model?): Vector3?
	local head = npc and npc:FindFirstChild("Head") :: Part?
	return head and head.Position
end

local function buildShop(pack: Pack, index: number, x0: number, root: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Shop" .. index
	folder.Parent = root

	-- floor, walls, entrance gap at the +Z end
	part({
		Name = "Floor",
		Size = Vector3.new(58, 1, 58),
		Position = Vector3.new(x0, 0, 6),
		Color = Color3.fromRGB(225, 214, 196),
		Material = Enum.Material.WoodPlanks,
		Parent = folder,
	})
	part({
		Name = "BackWall",
		Size = Vector3.new(58, 16, 1),
		Position = Vector3.new(x0, 8, -22.5),
		Color = Color3.fromRGB(188, 142, 102),
		Material = Enum.Material.Brick,
		Parent = folder,
	})
	for _, side in { -1, 1 } do
		part({
			Name = "SideWall",
			Size = Vector3.new(1, 16, 58),
			Position = Vector3.new(x0 + side * 29.5, 8, 6),
			Color = Color3.fromRGB(205, 170, 135),
			Material = Enum.Material.Brick,
			Parent = folder,
		})
	end

	-- menu board above the throne
	local board = part({
		Name = "MenuBoard",
		Size = Vector3.new(14, 7, 0.4),
		Position = Vector3.new(x0, 11.5, -22),
		Color = Color3.fromRGB(40, 44, 42),
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	local boardGui = Instance.new("SurfaceGui")
	boardGui.Face = Enum.NormalId.Back -- +Z face, toward the shop
	boardGui.CanvasSize = Vector2.new(520, 260)
	boardGui.Parent = board
	textLabel(boardGui, menuBoardText(pack), Enum.Font.Code, 26, Color3.fromRGB(240, 235, 210))

	-- the throne: dais, seat facing the counters, tall golden back
	part({
		Name = "Dais",
		Size = Vector3.new(12, 1.2, 8),
		Position = Vector3.new(x0, 1.1, THRONE_Z),
		Color = Color3.fromRGB(150, 40, 50),
		Material = Enum.Material.Fabric,
		Parent = folder,
	})
	local seat = Instance.new("Seat")
	seat.Name = "Throne"
	seat.Anchored = true
	seat.Size = Vector3.new(3.4, 1, 3)
	seat.CFrame = CFrame.new(x0, 2.2, THRONE_Z) * CFrame.Angles(0, math.pi, 0) -- face +Z
	seat.Color = Color3.fromRGB(226, 172, 52)
	seat.Material = Enum.Material.Metal
	seat.Parent = folder
	part({
		Name = "ThroneBack",
		Size = Vector3.new(3.8, 7, 0.8),
		Position = Vector3.new(x0, 5.2, THRONE_Z - 1.9),
		Color = Color3.fromRGB(226, 172, 52),
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	for _, side in { -1, 1 } do
		part({
			Name = "Armrest",
			Size = Vector3.new(0.6, 1.4, 3),
			Position = Vector3.new(x0 + side * 2, 3.1, THRONE_Z),
			Color = Color3.fromRGB(200, 150, 40),
			Material = Enum.Material.Metal,
			Parent = folder,
		})
	end

	-- shop sign over the entrance (out of the owner's line of sight): owner + live score
	local anchor = part({
		Name = "SignAnchor",
		Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(x0, 17, DOOR_Z),
		Transparency = 1,
		CanCollide = false,
		Parent = folder,
	})
	local signGui = Instance.new("BillboardGui")
	signGui.Size = UDim2.fromOffset(280, 70)
	signGui.MaxDistance = 250
	signGui.Parent = anchor
	local signTitle = textLabel(signGui, "Shop " .. index, Enum.Font.GothamBlack, 26, Color3.fromRGB(255, 255, 255))
	signTitle.Size = UDim2.new(1, 0, 0.55, 0)
	local signSub = textLabel(signGui, "open", Enum.Font.GothamBold, 18, Color3.fromRGB(255, 230, 170))
	signSub.Size = UDim2.new(1, 0, 0.45, 0)
	signSub.Position = UDim2.fromScale(0, 0.55)

	-- open/closed neon over the entrance
	local neon = part({
		Name = "OpenSign",
		Size = Vector3.new(8, 2.4, 0.4),
		Position = Vector3.new(x0, 12, DOOR_Z + 2),
		Color = Color3.fromRGB(200, 70, 70),
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	local neonGui = Instance.new("SurfaceGui")
	neonGui.Face = Enum.NormalId.Front -- -Z face, toward the inside
	neonGui.CanvasSize = Vector2.new(400, 120)
	neonGui.Parent = neon
	local neonLabel = textLabel(neonGui, "CLOSED", Enum.Font.GothamBlack, 64, Color3.fromRGB(255, 255, 255))

	local counters = {}
	for c, dx in COUNTER_OFFSETS do
		local cx = x0 + dx
		local counterFolder = Instance.new("Folder")
		counterFolder.Name = "Counter" .. c
		counterFolder.Parent = folder
		part({
			Name = "Counter",
			Size = Vector3.new(9, 3.6, 2.5),
			Position = Vector3.new(cx, 1.8, COUNTER_Z),
			Color = Color3.fromRGB(110, 76, 48),
			Material = Enum.Material.Wood,
			Parent = counterFolder,
		})
		part({
			Name = "Till",
			Size = Vector3.new(1.8, 1.4, 1.2),
			Position = Vector3.new(cx + 3, 4.3, COUNTER_Z),
			Color = Color3.fromRGB(60, 60, 66),
			Material = Enum.Material.Metal,
			Parent = counterFolder,
		})

		local staffSpot = Vector3.new(cx, 3, STAFF_Z)
		local customerSpot = Vector3.new(cx, 3, CUSTOMER_Z)
		local doorSpot = Vector3.new(cx, 3, DOOR_Z)
		local staffNpc: Model? = nil
		local customerNpc: Model? = nil

		local hooks = {}

		function hooks.spawnStaff(profile: StaffProfile)
			if staffNpc then
				staffNpc:Destroy()
			end
			-- new hires walk in from the door
			staffNpc = makeNpc(profile.name, "staff", LOOK_COLORS[profile.look] or Color3.fromRGB(235, 235, 230), 3, doorSpot, counterFolder)
			npcWalk(staffNpc, staffSpot, 2)
		end

		function hooks.despawnStaff()
			local npc = staffNpc
			staffNpc = nil
			if npc then
				npcSay(npc, nil)
				npcWalk(npc, doorSpot, 2)
				task.delay(2.1, function()
					npc:Destroy()
				end)
			end
		end

		-- one bubble per counter at a time: a real line hides the other speaker's
		function hooks.staffSay(text: string?)
			npcSay(staffNpc, text)
			if text and text ~= "…" then
				npcSay(customerNpc, nil)
			end
		end

		-- queue spot index -> walk to the throne; nil -> back behind the counter
		function hooks.staffWalkTo(queueSpot: number?)
			if queueSpot then
				local qx = x0 + QUEUE_OFFSETS[math.clamp(queueSpot, 1, #QUEUE_OFFSETS)]
				npcWalk(staffNpc, Vector3.new(qx, 3, QUEUE_Z), 2)
			else
				npcWalk(staffNpc, staffSpot, 2)
			end
		end

		function hooks.staffPosition(): Vector3?
			return headPosition(staffNpc)
		end

		function hooks.spawnCustomer(profile: CustomerProfile)
			if customerNpc then
				customerNpc:Destroy()
			end
			local height = if profile.ageGroup == "kid" then 2.2 else 3
			customerNpc = makeNpc(profile.name, "", LOOK_COLORS[profile.look] or Color3.fromRGB(180, 180, 180), height, doorSpot, counterFolder)
			npcWalk(customerNpc, customerSpot - Vector3.new(0, (3 - height) / 2, 0), 1.4)
		end

		function hooks.despawnCustomer()
			local npc = customerNpc
			customerNpc = nil
			if npc then
				npcSay(npc, nil)
				npcWalk(npc, doorSpot, 1.3)
				task.delay(1.4, function()
					npc:Destroy()
				end)
			end
		end

		function hooks.customerSay(text: string?)
			npcSay(customerNpc, text)
			if text and text ~= "…" then
				npcSay(staffNpc, nil)
			end
		end

		function hooks.customerPosition(): Vector3?
			return headPosition(customerNpc)
		end

		counters[c] = hooks
	end

	local shop = {}
	shop.counters = counters
	shop.throne = seat

	function shop.setSign(title: string, subtitle: string)
		signTitle.Text = title
		signSub.Text = subtitle
	end

	function shop.setOpen(open: boolean)
		neon.Color = if open then Color3.fromRGB(70, 180, 110) else Color3.fromRGB(200, 70, 70)
		neonLabel.Text = if open then "OPEN" else "CLOSED"
	end

	return shop
end

function WorldBuilder.build(pack: Pack, shopCount: number)
	local root = Instance.new("Folder")
	root.Name = "KidSimWorld"
	root.Parent = workspace

	-- fallback spawn on a plaza behind the shops; owners get seated on thrones
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Size = Vector3.new(4, 1, 4)
	spawnLocation.Position = Vector3.new(0, 0.5, -30)
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Transparency = 1
	spawnLocation.CanCollide = false
	spawnLocation.Duration = 0
	spawnLocation.Parent = root
	part({
		Name = "Plaza",
		Size = Vector3.new(shopCount * SHOP_SPACING + 20, 1, 20),
		Position = Vector3.new(0, 0, -33),
		Color = Color3.fromRGB(200, 196, 186),
		Material = Enum.Material.Concrete,
		Parent = root,
	})

	local shops = {}
	for index = 1, shopCount do
		local x0 = (index - (shopCount + 1) / 2) * SHOP_SPACING
		shops[index] = buildShop(pack, index, x0, root)
	end
	return { shops = shops }
end

return WorldBuilder
