--!strict
-- Server-only LLM client over HttpService against any OpenAI-compatible
-- /chat/completions endpoint. The API key is resolved server-side only:
-- Creator Hub secret first, gitignored DevSecrets module second.

local HttpService = game:GetService("HttpService")

local Config = require(script.Parent.Config)

export type ChatMessage = { role: string, content: string }
export type ChatOptions = {
	maxTokens: number?,
	temperature: number?,
}

local LlmClient = {}

type Settings = {
	auth: Secret | string,
	baseUrl: string,
	model: string,
}

local cachedSettings: Settings? = nil
local warnedOnce = false

local function resolveSettings(): Settings?
	if cachedSettings then
		return cachedSettings
	end

	local baseUrl: string = Config.BASE_URL
	local model: string = Config.MODEL

	local devModule = script.Parent:FindFirstChild("DevSecrets")
	local devKey: string? = nil
	if devModule and devModule:IsA("ModuleScript") then
		local ok, dev = pcall(require, devModule)
		if ok and typeof(dev) == "table" then
			if typeof(dev.API_KEY) == "string" and #dev.API_KEY > 0 then
				devKey = dev.API_KEY
			end
			if typeof(dev.BASE_URL) == "string" and #dev.BASE_URL > 0 then
				baseUrl = dev.BASE_URL
			end
			if typeof(dev.MODEL) == "string" and #dev.MODEL > 0 then
				model = dev.MODEL
			end
		end
	end

	-- Creator Hub secret wins when available (published experience).
	local okSecret, secret = pcall(function()
		return HttpService:GetSecret(Config.SECRET_NAME)
	end)
	if okSecret and secret then
		cachedSettings = {
			auth = secret:AddPrefix("Bearer "),
			baseUrl = baseUrl,
			model = model,
		}
		return cachedSettings
	end

	if devKey then
		cachedSettings = {
			auth = "Bearer " .. devKey,
			baseUrl = baseUrl,
			model = model,
		}
		return cachedSettings
	end

	if not warnedOnce then
		warnedOnce = true
		warn(
			"[KidSim] No LLM key found. Add a Creator Hub secret named '"
				.. Config.SECRET_NAME
				.. "' or copy DevSecrets.example.luau to DevSecrets.luau. "
				.. "Running with scripted fallback lines only."
		)
	end
	return nil
end

function LlmClient.isConfigured(): boolean
	return resolveSettings() ~= nil
end

-- Returns (true, replyText) or (false, errorMessage). Retries once.
function LlmClient.chat(messages: { ChatMessage }, opts: ChatOptions?): (boolean, string)
	local settings = resolveSettings()
	if not settings then
		return false, "no-api-key"
	end

	local options: ChatOptions = opts or {}
	local body = HttpService:JSONEncode({
		model = settings.model,
		messages = messages,
		max_tokens = options.maxTokens or Config.MAX_TOKENS_DIALOGUE,
		temperature = options.temperature or 0.7,
	})

	local lastErr = "unknown"
	for attempt = 1, 2 do
		local ok, response = pcall(function()
			return HttpService:RequestAsync({
				Url = settings.baseUrl .. "/chat/completions",
				Method = "POST",
				Headers = {
					["Content-Type"] = "application/json",
					["Authorization"] = settings.auth,
				},
				Body = body,
			})
		end)

		if ok and response.Success then
			local okJson, data = pcall(function()
				return HttpService:JSONDecode(response.Body)
			end)
			if okJson and data.choices and data.choices[1] and data.choices[1].message then
				local content = data.choices[1].message.content
				if typeof(content) == "string" and #content > 0 then
					return true, content
				end
			end
			lastErr = "bad-response-shape"
		elseif ok then
			lastErr = "http-" .. tostring(response.StatusCode) .. ": " .. string.sub(response.Body or "", 1, 200)
		else
			lastErr = tostring(response)
		end

		if attempt == 1 then
			task.wait(1)
		end
	end

	warn("[KidSim] LLM call failed: " .. lastErr)
	return false, lastErr
end

return LlmClient
