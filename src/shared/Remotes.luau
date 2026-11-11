--!strict
-- Shared remote registry. The server creates every remote up front;
-- the client waits for them. One folder, flat names.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "KidSimRemotes"

-- server -> client: Phase, State, Questions, Speak, Debrief, Toast,
--                   Leaderboard, Timer
-- client -> server: StartRound, Continue, SetPolicy, Answer, StaffAction
local NAMES = {
	"Phase", "State", "Questions", "Speak", "Debrief", "Toast", "Leaderboard", "Timer",
	"StartRound", "Continue", "SetPolicy", "Answer", "StaffAction",
}

local Remotes = {}

local function getFolder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder?
		if not folder then
			folder = Instance.new("Folder")
			assert(folder, "folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder :: Folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Remotes.get(name: string): RemoteEvent
	local folder = getFolder()
	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name) :: RemoteEvent?
		if not remote then
			remote = Instance.new("RemoteEvent")
			assert(remote, "remote")
			remote.Name = name
			remote.Parent = folder
		end
		return remote :: RemoteEvent
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

-- Server-side bootstrap so the client never races folder creation.
function Remotes.init()
	for _, name in NAMES do
		Remotes.get(name)
	end
end

return Remotes
