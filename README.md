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
Client (world, HUD, dialogue, choices)
  -> RemoteEvents
Server (pack loader, world state, event loop, scoring)   <- the product
  -> HttpService -> any OpenAI-compatible LLM API
       personas: counterpart, coach, evaluator
```

- **`src/server/SimEngine.luau`** — loads a pack, owns authoritative state
  (generic meters + inventory), runs `Intro → Shift (incidents) → Close → Debrief`,
  keeps the shift log. Zero cafe concepts in this file.
- **`src/server/AgentRuntime.luau`** — three personas, prompts supplied by the pack:
  - *Counterpart*: the in-world person (orders, bargains, complains). Free-chat,
    stays in character, age-guardrailed.
  - *Coach*: at most one short hint per incident; nudges, never plays for the child.
  - *Evaluator*: reads the full shift log + state and returns structured JSON —
    skills practiced, evidence, real-world transfer, one next drill.
- **`src/server/Packs/CafeShift.luau`** — tonight's pack. Starting cash/stock, five
  incidents (a bargainer demanding 50% off, a wrong-order complaint, an
  overpromise trap, a freebie request...), every prompt and every number.
  A new pack = a new module; the engine does not change.
- **`src/server/WorldBuilder.luau`** — the whole map is generated from code, so the
  repo is the entire game. No binary place file needed.
- **`src/client/Main.client.luau`** — HUD (meters defined by the pack), dialogue +
  choice UI, coach bubble, and the full-screen **sim-to-real debrief**: numbers
  before→after, skills in plain English, "in the real world this is called…",
  one next drill.

Decision outcomes are deterministic (choices carry state deltas, the server is
authoritative), while the LLM provides the conversation, the hinting, and the
evaluation — so the loop stays playable even if a model call fails.

## Run it in Studio

Prereqs: [Roblox Studio](https://create.roblox.com/), [Rojo](https://rojo.space/)
(`brew install rojo`).

```bash
git clone <this repo> && cd kidsim
rojo build -o kidsim.rbxlx     # or: rojo serve + the Rojo Studio plugin
open kidsim.rbxlx
```

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
2. A cafe shift starts. An agent customer bargains for 50% off.
3. The player decides; cash and reputation move live on the HUD.
4. A complaint hits; the coach whispers one hint if asked.
5. Shift ends → debrief: the real numbers from this shift, the skills by name
   (cash flow, customer service, saying no kindly), one next drill.

## Safety

- Age-appropriate by construction: guardrails ride in every pack persona prompt.
- API keys live in Creator Hub secrets or a gitignored module; never in client
  scripts, never in the repo.
