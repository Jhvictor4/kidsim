# Studio setup — the manual steps (10 minutes)

Everything in the repo is code; these are the only steps that need human hands
in Roblox Studio. Do them in order.

## 1. Build and open the place

```bash
rojo build -o kidsim.rbxlx
open kidsim.rbxlx
```

(Alternative for live-reload development: `rojo serve`, then connect with the
Rojo plugin in Studio.)

## 2. Publish the experience

File → **Publish to Roblox** → new experience, any name (e.g. "KidSim — Cafe
Shift"). HttpService and secrets do not work in an unpublished place.

## 3. Allow HTTP requests

Home → **Game Settings** → **Security** → **Allow HTTP Requests** → On → Save.

## 4. Give the server an LLM key (pick one)

**A. Creator Hub secret (production / published game)**

1. [create.roblox.com](https://create.roblox.com) → Creations → your experience
   → **Secrets** → Create Secret.
2. Name: `LLM_API_KEY` (exactly). Value: the raw API key (no "Bearer ").
3. Applicable domain: `api.gmi-serving.com` (or `api.openai.com` if you switch
   providers in Config).

**B. DevSecrets module (Studio playtest, fastest)**

```bash
cp src/server/DevSecrets.example.luau src/server/DevSecrets.luau
# paste the key into API_KEY; optionally override BASE_URL / MODEL
rojo build -o kidsim.rbxlx   # rebuild (or let rojo serve sync it)
```

`DevSecrets.luau` is gitignored. Never put the key anywhere else.

## 5. Verify the round trip

Press **Play** in Studio. In the Output window you should see:

```
[KidSim] Pack loaded: Cafe Shift (cafe_shift)
[KidSim] LLM configured: true
```

Click **Start the round**, type anything to the first customer, and a model-written
reply should appear within a couple of seconds. If the model is unreachable you
get scripted fallback lines and a warning in Output — the shift still completes.

Key-safety check: the key exists only in the Creator Hub secret store and/or
`src/server/DevSecrets.luau` (a server ModuleScript). Nothing under
`StarterPlayer` / ReplicatedStorage ever sees it.

## 6. Record the demo

90 seconds, English: thesis card → round start with a friend → persuading a random customer (coach hint once) → results + debrief.
The debrief shows the real numbers from the round just played. For a two-player
recording use Studio's Test → Clients and Servers (2 players) or two devices.
