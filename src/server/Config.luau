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
	MAX_TOKENS_EVALUATION = 700,

	-- Round
	ROUND_SECONDS = 180,
	COUNTDOWN_SECONDS = 3,
	MAX_LANES = 4,

	-- Customers
	CUSTOMER_IDLE_SECONDS = 35, -- customer gives up if the shopkeeper says nothing
	GAP_BETWEEN_CUSTOMERS = 1.5,
	COACH_HINTS_PER_CUSTOMER = 1,

	-- Score = revenue + STARS_WEIGHT * sum(stars - 3).
	-- A pushy sale that leaves a 1-star customer costs $4 of score.
	STARS_WEIGHT = 2,
	-- Word of mouth: the lane's average stars scale the next customer's wallet.
	-- 3 stars = x1.0, each star above/below = +/- BUZZ_PER_STAR, clamped.
	BUZZ_PER_STAR = 0.15,
	BUZZ_MIN = 0.7,
	BUZZ_MAX = 1.3,
}
