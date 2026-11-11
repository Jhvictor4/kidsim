# KidSim — Isaac Sim for children

**Practice real skills in Roblox. Take them into the real world.**

[NVIDIA Isaac Sim](https://developer.nvidia.com/isaac/sim) lets robots rehearse in a
high-fidelity simulator before they act in the real world. KidSim does the same for
kids: **Roblox is the simulator**. AI agents are the environment, the other people,
and the scoring function. The child practices a real skill in-world, then gets a
debrief that names the skill and how it transfers to real life.

Built at the c0mpiled-18 YC Startup School Hackathon. Pitch frame: YC RFS
["The $15-an-Hour Expert"](https://www.ycombinator.com/rfs).

## The engine, not the cafe

A cafe, a courtroom, a negotiation, accounting — those are **scenario packs**
plugged into one pack-agnostic engine:

```
Client (lobby, HUD, live leaderboard, chat with the customer, results)
  -> RemoteEvents
Server (round manager, one lane engine per player, sale validation, scoring)   <- the product
  -> HttpService -> any OpenAI-compatible LLM API
       personas: customer agent, coach, evaluator
```

Every customer is an **agent**. The server rolls a random customer (age, visible
situation, hidden wallet, hidden taste, price attitude, patience); an LLM plays them.
The child talks freely; the customer decides — keep talking, buy, or leave — and how
many stars to give. Score = **revenue + happiness** (`revenue + 2 × Σ(stars − 3)`),
and happy customers bring fuller wallets to that counter (word of mouth).
Friends play side by side: one counter lane each, a 3-minute round, a live leaderboard.

- **`src/server/RoundManager.luau`** — lobby → countdown → timed round → results,
  lane assignment per player, live leaderboard, parallel debriefs.
- **`src/server/LaneEngine.luau`** — one player's counter for one round: pulls
  customers, runs the conversation, and **validates** every proposed sale against
  the menu price (never overcharged; discounts allowed), stock and the wallet.
- **`src/server/CustomerGen.luau`** — random customer profiles from the pack's ranges;
  only name/age/situation ever reach the client.
- **`src/server/AgentRuntime.luau`** — three personas, prompts supplied by the pack:
  - *Customer*: answers in JSON (`say`, `decision`, `items`, `pay`, `stars`), stays
    in character, age-guardrailed, keeps its wallet private.
  - *Coach*: one short hint per customer; sees only what the child sees.
  - *Evaluator*: reads every customer record (hidden profile, what the child said,
    what sold, stars) and returns structured JSON — skills, evidence, real-world
    transfer, one next drill.
- **`src/server/Packs/CafeShift.luau`** — the menu, stock, customer ranges and every
  prompt. A new pack = a new module; the engine does not change.
- **`src/server/WorldBuilder.luau`** — the whole map (N counter lanes with live score
  signs) is generated from code, so the repo is the entire game.
- **`src/client/Main.client.luau`** — lobby card, HUD, leaderboard, conversation log,
  coach bubble, and the results + **sim-to-real debrief** ("you earned $14 of the $59
  in their wallets", per-customer outcomes, skills, real-world transfer, next drill).

The LLM proposes, the server decides: money, stock and score only change through
server-side validation, and if a model call fails the customer just runs out of
patience — the round always finishes.

## Run it in Studio

Prereqs: [Roblox Studio](https://create.roblox.com/), [Rojo](https://rojo.space/)
(`brew install rojo`).

```bash
git clone <this repo> && cd kidsim
rojo build -o kidsim.rbxlx     # or: rojo serve + the Rojo Studio plugin
open kidsim.rbxlx
```

No Rojo? Open the prebuilt bundle `dist/kidsim.rbxlx` (File → Open from File) instead.
It is built from `main` **without** `DevSecrets.luau`, so it holds no API key —
you still do step 3 below. Rebuild it after changing `src/`:
`mv src/server/DevSecrets.luau /tmp/ && rojo build -o dist/kidsim.rbxlx && mv /tmp/DevSecrets.luau src/server/`.

Then in Studio (one-time, see `SETUP.md` for details):

1. **Publish** the experience (File → Publish). HttpService needs a published place.
2. Game Settings → Security → **Allow HTTP Requests** = On.
3. Give the server an LLM key — either
   - **Creator Hub secret** named `LLM_API_KEY` (production path), or
   - copy `src/server/DevSecrets.example.luau` → `src/server/DevSecrets.luau`
     and paste a key (gitignored dev path).
4. Press **Play**. The key never reaches a client script; all LLM calls run on the
   server through `HttpService`.

Default endpoint is GMI Cloud (`https://api.gmi-serving.com/v1`, OpenAI-compatible);
override `BASE_URL` / `MODEL` in `DevSecrets.luau` to use any other provider.

## The 90-second demo

1. Thesis on screen: *Isaac Sim, but for kids.*
2. Two friends, two counters, one 3-minute round. The leaderboard is live.
3. A random customer walks up ("cold from the rain"); the kid asks, suggests
   hot chocolate, upsells a cookie, hears "I only have $4", offers a fair deal.
4. Stuck? The coach whispers one hint.
5. Time's up → results: rank, "you earned $X of the $Y in their wallets",
   each customer's stars, the skills by name, one next drill.

## Safety

- Age-appropriate by construction: guardrails ride in every pack persona prompt.
- API keys live in Creator Hub secrets or a gitignored module; never in client
  scripts, never in the repo.
