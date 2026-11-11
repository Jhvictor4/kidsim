--!strict
-- Memory layer: GBrain (https://github.com/garrytan/gbrain), called over its
-- MCP HTTP endpoint (JSON-RPC `tools/call`, one stateless POST per call).
--
-- KidSim remembers one thing per owner per round: an anonymous skill record
-- (no names, no chat text — the players are children). The owner key is a
-- salted hash of the Roblox UserId. Next round reads the latest record to
-- shape the team and the coach tips, and the debrief shows growth.
--
-- Uses only GBrain's memory verbs:
--   remember {fact, entity, provenance, kind}   recall {entity}
-- If GBrain is not configured or unreachable, every call returns nil and
-- the game behaves exactly as it does without memory.
--
-- Configuration (server only, never in the repo):
--   URL   : Config.GBRAIN_URL, or DevSecrets.GBRAIN_URL (the brain's /mcp URL)
--   token : Creator Hub secret Config.GBRAIN_SECRET_NAME, or DevSecrets.GBRAIN_TOKEN
--           (a GBrain API key with read,write scopes)

local HttpService = game:GetService("HttpService")

local Config = require(script.Parent.Config)

local GBrainClient = {}

type Settings = { url: string, auth: Secret | string }

local cached: Settings? = nil
local resolved = false
local warned = false

local RECORD_TAG = "KIDSIM_ROUND"

local function settings(): Settings?
	if resolved then
		return cached
	end
	resolved = true

	local url: string = Config.GBRAIN_URL or ""
	local devToken: string? = nil
	local devModule = script.Parent:FindFirstChild("DevSecrets")
	if devModule and devModule:IsA("ModuleScript") then
		local ok, dev = pcall(require, devModule)
		if ok and typeof(dev) == "table" then
			if typeof(dev.GBRAIN_URL) == "string" and #dev.GBRAIN_URL > 0 then
				url = dev.GBRAIN_URL
			end
			if typeof(dev.GBRAIN_TOKEN) == "string" and #dev.GBRAIN_TOKEN > 0 then
				devToken = dev.GBRAIN_TOKEN
			end
		end
	end

	local auth: (Secret | string)? = nil
	local okSecret, secret = pcall(function()
		return HttpService:GetSecret(Config.GBRAIN_SECRET_NAME)
	end)
	if okSecret and secret then
		auth = secret:AddPrefix("Bearer ")
	elseif devToken then
		auth = "Bearer " .. devToken
	end

	if #url == 0 or auth == nil then
		print("[KidSim] GBrain memory: off (no URL/token configured)")
		return nil
	end
	cached = { url = url, auth = auth :: Secret | string }
	print("[KidSim] GBrain memory: on")
	return cached
end

function GBrainClient.isConfigured(): boolean
	return settings() ~= nil
end

-- Anonymous, stable owner key: FNV-1a over salt .. UserId. Not reversible
-- to a name, and the salt keeps it from matching other games' ids.
function GBrainClient.ownerEntity(userId: number): string
	local text = Config.GBRAIN_ENTITY_SALT .. ":" .. tostring(userId)
	local hash = 2166136261
	for i = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, i))
		hash = (hash * 16777619) % 4294967296
	end
	return string.format("kidsim-owner-%08x", hash)
end

-- The MCP HTTP transport may answer as plain JSON or as an SSE stream
-- ("event: message\ndata: {...}"); take the last JSON-RPC message.
local function decodeRpc(body: string): { [string]: any }?
	local payload = body
	if not body:match("^%s*{") then
		local last: string? = nil
		for line in body:gmatch("[^\r\n]+") do
			local data = line:match("^data:%s*(.*)$")
			if data and #data > 0 then
				last = data
			end
		end
		if not last then
			return nil
		end
		payload = last
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(payload)
	end)
	if ok and typeof(decoded) == "table" then
		return decoded
	end
	return nil
end

local function callTool(name: string, arguments: { [string]: any }): { [string]: any }?
	local s = settings()
	if not s then
		return nil
	end
	local body = HttpService:JSONEncode({
		jsonrpc = "2.0",
		id = HttpService:GenerateGUID(false),
		method = "tools/call",
		params = { name = name, arguments = arguments },
	})
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = s.url,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["Accept"] = "application/json, text/event-stream",
				["Authorization"] = s.auth,
			},
			Body = body,
		})
	end)
	if not ok or not response.Success then
		if not warned then
			warned = true
			local why = if ok then "http-" .. tostring(response.StatusCode) else tostring(response)
			warn("[KidSim] GBrain unreachable, playing without memory: " .. string.sub(why, 1, 160))
		end
		return nil
	end
	local rpc = decodeRpc(response.Body)
	if not rpc or rpc.error or not rpc.result then
		warn("[KidSim] GBrain " .. name .. " returned an error: " .. string.sub(response.Body, 1, 200))
		return nil
	end
	local result = rpc.result
	if result.isError then
		warn("[KidSim] GBrain " .. name .. " refused: " .. string.sub(response.Body, 1, 200))
		return nil
	end
	-- tools return their payload as JSON text in content[1]
	local content = result.content
	local text = typeof(content) == "table" and content[1] and content[1].text
	if typeof(text) ~= "string" then
		return nil
	end
	local okText, data = pcall(function()
		return HttpService:JSONDecode(text)
	end)
	if okText and typeof(data) == "table" then
		return data
	end
	return nil
end

-- Save one round record for this owner. Fire-and-forget friendly.
function GBrainClient.rememberRound(entity: string, record: { [string]: any }): boolean
	local result = callTool("remember", {
		fact = RECORD_TAG .. " " .. HttpService:JSONEncode(record),
		entity = entity,
		kind = "event",
		provenance = "KidSim round record, " .. DateTime.now():ToIsoDate(),
	})
	return result ~= nil and (result.status == "inserted" or result.id ~= nil)
end

-- The owner's most recent round record, or nil (none yet / memory off).
function GBrainClient.lastRound(entity: string): { [string]: any }?
	local result = callTool("recall", { entity = entity })
	if not result or typeof(result.facts) ~= "table" then
		return nil
	end
	local newest: { [string]: any }? = nil
	local newestAt = ""
	for _, fact in result.facts do
		local text = typeof(fact) == "table" and fact.fact
		if typeof(text) == "string" then
			-- recall wraps stored text in a quote fence; the record is the {...} after the tag
			local json = text:match(RECORD_TAG .. "%s*(%b{})")
			if json then
				local ok, record = pcall(function()
					return HttpService:JSONDecode(json)
				end)
				local at = typeof(fact.created_at) == "string" and fact.created_at or ""
				if ok and typeof(record) == "table" and at >= newestAt then
					newest = record
					newestAt = at
				end
			end
		end
	end
	return newest
end

return GBrainClient
