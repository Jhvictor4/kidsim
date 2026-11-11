--!strict
-- Copy this file to DevSecrets.luau (same folder) and fill it in for
-- Studio playtests. DevSecrets.luau is gitignored — NEVER commit a key,
-- and never put a key in any client script.
--
-- In the published experience, prefer a Creator Hub secret named
-- "LLM_API_KEY" instead; this file is only the local-dev fallback.

return {
	API_KEY = "", -- sk-... / gmi key

	-- Optional overrides (leave nil to use Config defaults)
	BASE_URL = nil :: string?, -- e.g. "https://api.openai.com/v1"
	MODEL = nil :: string?, -- e.g. "gpt-4o-mini"
}
