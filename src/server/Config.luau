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

	-- LLM budgets
	MAX_TOKENS_CUSTOMER = 220, -- JSON turn: say + decision + items
	MAX_TOKENS_STAFF = 200, -- JSON turn: say + action (+ question)
	MAX_TOKENS_EVALUATION = 800,

	-- Round
	ROUND_SECONDS = 180,
	COUNTDOWN_SECONDS = 3,
	MAX_SHOPS = 4, -- one shop per player

	-- Staff
	STAFF_PER_SHOP = 3,
	HIRE_DELAY_SECONDS = 8, -- empty counter after a firing
	HIRE_FEE = 5, -- score cost of every new hire after the first team
	OWNER_ANSWER_SECONDS = 20, -- staff wait this long at the throne, then decide alone
	GAP_BETWEEN_CUSTOMERS = 2,

	-- Score = revenue - hiring fees + STARS_WEIGHT * sum(stars - 3).
	STARS_WEIGHT = 2,
	-- Word of mouth: a shop's average stars scale the next customer's wallet.
	BUZZ_PER_STAR = 0.15,
	BUZZ_MIN = 0.7,
	BUZZ_MAX = 1.3,

	-- Text-to-speech voices (AudioTextToSpeech.VoiceId), English only so the
	-- spoken line matches the bubble.
	TTS_VOICES = { "1", "2", "3", "4", "5", "6", "7", "8" },
}
