--!strict
-- Non-secret runtime configuration. Secrets never live here.
--
-- Key resolution order (see LlmClient):
--   1. Creator Hub secret named SECRET_NAME (published experience)
--   2. src/server/DevSecrets.luau (gitignored, see DevSecrets.example.luau)

return {
	-- Creator Hub secret name (Creator Dashboard -> your experience -> Secrets)
	SECRET_NAME = "LLM_API_KEY",

	-- Any OpenAI-compatible endpoint. GMI Cloud (event credits) by default;
	-- DevSecrets.luau can override both of these.
	BASE_URL = "https://api.gmi-serving.com/v1",
	MODEL = "openai/gpt-oss-120b",

	-- Dialogue budget
	MAX_TOKENS_DIALOGUE = 140,
	MAX_TOKENS_EVALUATION = 600,

	-- Per-incident coach hint limit
	COACH_HINTS_PER_INCIDENT = 1,
}
