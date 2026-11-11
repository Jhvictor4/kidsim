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
Client (lobby, HUD, staff cards, house-rule chips, staff questions, TTS, results)
  -> RemoteEvents
Server (round manager, one shop engine per owner, sale + rule validation, scoring)   <- the product
  -> HttpService -> any OpenAI-compatible LLM API
       personas: customer agent, staff agent, evaluator
```

**The child is the owner.** They sit on a throne in their own cafe. Three **staff
agents** run the counters, each with a hidden personality (Star, Pushover, Pushy
seller, Grumpy, Worrier). Random **customer agents** walk in (hidden wallet, taste,
price attitude). Staff and customers talk to each other on their own — speech
bubbles in the world, read aloud with Roblox text-to-speech. The owner:

- sets the **house rules** (discounts, how hard to sell, when to ask the boss) with
  chips — nothing is ever typed;
- answers staff who **walk to the throne** with a question (2–3 buttons; no answer
  in 20 s and they decide alone);
- reads the evidence (sales, stars, rule breaks, complaints) and **praises, warns or
  fires** — a fired counter gets a new random hire after a short wait (hiring fee).

Score = **revenue − hiring fees + 2 × Σ(stars − 3)**; happy customers bring fuller
wallets (word of mouth). Friends each own a shop side by side in one server; a live
leaderboard compares owners, and the debrief reveals who each staff member really was.

- **`src/server/RoundManager.luau`** — lobby → countdown → timed round → results,
  one shop per player, seats owners on their thrones, leaderboard, parallel debriefs.
- **`src/server/ShopEngine.luau`** — one owner's shop for one round: three counter
  loops (staff ↔ customer conversations), the question queue, praise/warn/fire/hire,
  and **validation** of every sale (menu price, stock, wallet) plus rule-break checks
  against the owner's current rules.
- **`src/server/CustomerGen.luau`** — random customers and staff from the pack's ranges,
  each with its own TTS voice.
- **`src/server/AgentRuntime.luau`** — the personas, prompts supplied by the pack:
  - *Customer*: JSON (`say`, `decision`, `items`, `pay`, `stars`, `complaint`).
  - *Staff*: JSON (`say`, `action`: talk / ask_owner, `question`, `options`); follows
    (or bends) the owner's rules according to its hidden personality and the
    owner's praise/warnings.
  - *Evaluator*: reads the whole round (rules, owner actions with timings, every sale,
    each staff member's hidden personality) and returns skills, evidence,
    real-world transfer and one next drill.
- **`src/server/Packs/CafeShift.luau`** — menu, stock, customer ranges, staff
  personalities, house-rule options and every prompt. A new pack = a new module.
- **`src/server/WorldBuilder.luau`** — the map (shops with a throne, three counters,
  queue spots, live signs) is generated from code.
- **`src/client/Main.client.luau`** — lobby, HUD, staff cards, rule chips, question
  card, text-to-speech (silent fallback), throne overview camera, results + debrief.

The LLM proposes, the server decides: money, stock, rule breaks and score only change
through server-side validation, and if a model call fails the round still finishes.

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
2. You own a cafe. Three staff walk in; each one has a secret personality.
3. Staff and customers talk on their own (bubbles + voices). One staff member walks
   to your throne: "Can I give 30% off?" — you tap an answer.
4. A ⚠ appears: someone broke your discount rule. You warn — then fire. A new hire walks in.
5. Time's up → leaderboard vs your friend → "Jake was really a Pushover" → the skills
   you practiced (clear rules, judging people by what they do, fair feedback).

## Safety

- Age-appropriate by construction: guardrails ride in every pack persona prompt.
- API keys live in Creator Hub secrets or a gitignored module; never in client
  scripts, never in the repo.
