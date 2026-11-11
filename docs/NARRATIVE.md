# KidSim — company narrative (draft v1, 2026-11-11)

## One line
**KidSim turns a financial-literacy standard into a Roblox scenario kids actually play — AI characters are the customers, the staff and the grader, and it remembers each kid's growth.**

## Form: Project Description (1–2 sentences)
> KidSim is Isaac Sim for children: give it a skill and a rubric, and it spins up a playable Roblox scenario where AI agents are the people and the grader. Our first pack teaches money and people skills by letting kids run a cafe, with GBrain remembering each kid so the next round targets their weak skill.

## The story (≈60 s spoken)
1. **Problem.** Robots rehearse in a simulator before the real world. Kids don't. The money and people skills they need — pricing, saying no to a discount, spotting who's not pulling their weight — they learn by failing in real life, usually expensively.
2. **Why now.** Personal finance just became school infrastructure: **30 US states now require a standalone personal finance course to graduate** (NGPF, Apr 2026), up from 28 a year earlier, with California joining from the class of 2030–31. Schools must teach it; they mostly teach it with worksheets. Meanwhile the kids are already on Roblox.
3. **Product.** A pack-agnostic engine on Roblox. A *pack* = a scenario + the skills it measures. AI agents play every other person (customers with hidden wallets, staff with hidden personalities) and an evaluator agent grades the round against the rubric. The debrief names the skill, the evidence, and how it transfers to real life.
4. **The loop that compounds.** GBrain stores an anonymous skill record per kid after every round; the next round is built to probe the weak skill. Growth is visible (“Answering your team: 0/1 → 2/2”). That growth record is what a teacher or parent actually buys.
5. **Wedge.** Financial literacy for ages 10–15: standards already exist, the requirement already exists, and outcomes are measurable. The cafe pack is lesson one (pricing, discounts, revenue vs. costs, managing people).
6. **Business.** Free to play on Roblox (distribution). Paid by the people who need proof: (a) teachers/schools — class dashboard mapped to the state standard, (b) parents — progress reports, (c) sponsors who already fund financial literacy (banks, credit unions, nonprofits) — branded packs.
7. **Why us / moat.** Not the 3D world — the *environment + grader + memory*. Every round produces labeled data on how kids handle money and people decisions; packs get better and the memory gets deeper.
8. **Vision.** One engine, any real-world skill: negotiation, a first job, a courtroom, a budget. Roblox is the first channel, not the dependency.

## Risks we answer up front
- **Platform:** Roblox policy on external AI calls / chat for under-13s. Answer: the engine is pack-agnostic and server-side; Roblox is the first channel.
- **Child safety & privacy (COPPA):** no names or chat text stored (salted-hash key), kids never type, LLM output filtered server-side.
- **“Is it learning or a game?”** The evaluator + growth record is the evidence; the next step is a classroom pilot measuring pre/post on the state standard.

## Numbers to verify before saying them on stage
- 30 states (standalone course) — NGPF Annual Report 2026. 39 if counting personal finance embedded in other courses (CEE 2026 survey). Say “30”, cite NGPF.
- Roblox audience size and under-13 share — pull from Roblox's latest earnings release, not memory.
