# Core Rules — Non-Negotiable Baseline

This file is the single canonical statement of the rules every Skill in this
system must obey without exception. It was extracted from the existing
`Amazon-products` engine (code + 568 passing tests + docs + historical reports)
on 2026-08-16. Domain reference files elaborate on these; this file is what to
re-read whenever a Skill's instructions seem to conflict with something else.

**Architecture premise: this system wraps the existing engine — it does not
reimplement it.** Every rule below is enforced by *tested Python code already
in `Amazon-products`*, driven through the commands in
`cli-command-reference.md`. A Skill's job is to call the right command at the
right time with the right evidence, and to never claim a result the engine
itself didn't produce. If a Skill's instructions and the engine's actual
behavior ever disagree, the engine's behavior wins — update the Skill, never
route around the engine.

---

## The five safety-critical rules (verified in code + tests, cannot be overridden)

1. **Hard gates fire only on literal `CONFIRMED_*` values.**
   `CONFIRMED_CONTAMINATION`, `CONFIRMED_BLOCKER`, `CONFIRMED_IMPOSSIBLE` — and
   nothing else — can reject a candidate via a hard gate. `UNKNOWN`,
   `SUSPECTED_CONTAMINATION`, `PENDING_HUMAN_LEGAL_REVIEW`,
   `MANUAL_SOURCING_REQUIRED` **never** fire a gate. (`engine/ranking/gates.py`,
   module docstring calls this "CRITICAL INVARIANT, enforced by tests.")
   → Never tell a human a candidate was rejected because of a *suspected* or
   *pending* status — those are reasons to seek more evidence, not to reject.

2. **`QUALIFIED` is reachable only through `hunt decide approve`, run by an
   actual human.** No Skill, no automated stage, no LLM output can set
   `QUALIFIED`. A Skill's job stops at `PROMISING` / `HUMAN_REVIEW` and a
   clear recommendation — the decision itself belongs to the person, always.

3. **`--mode real` never silently falls back to mock data.** If a real
   provider isn't credentialed/terms-acknowledged/capable, the engine
   hard-stops with `RealDataProviderRequired` / exit code 1. A Skill must
   never interpret that failure as "proceed with mock data instead" without
   the human explicitly choosing to.

4. **Economics is deterministic Python, never natural-language arithmetic.**
   `hunt economics-set`/`economics-show` call the real calculator. Missing a
   required field (`selling_price`, `unit_cost`, `referral_fee_pct`,
   `fulfillment_fee_per_unit`) returns `INSUFFICIENT_DATA`, never a guess.
   Every optional field defaulted to zero is disclosed in
   `fields_treated_as_unknown`. A Skill must never compute margin/ROI/breakeven
   itself — only ever report what `economics-set`/`economics-show` returned.

5. **Evidence can only be downgraded, never upgraded, by inference.**
   `FACT` is reserved for first-party providers or direct human/Claude-Browser
   observation (`HUMAN_VERIFIED`). Automated provider data caps at `ESTIMATE`.
   External browser research caps at `ESTIMATE`, **never** `FACT` — it is a
   distinct trust tier (`EXTERNAL_BROWSER_RESEARCH`), never conflated with
   `HUMAN_VERIFIED` or `LLM_INFERENCE`. Freshness/contradiction overrides can
   only push status *down* (e.g. `STALE`, `CONTRADICTED`), never up.

---

## The anti-hallucination contract

Never perform any of these conversions, regardless of how confident the
research makes something feel:

| Never convert | Into |
|---|---|
| `UNKNOWN` | `FACT` |
| `UNKNOWN` | `ESTIMATE` |
| `INSUFFICIENT_DATA` | `PASS` |
| `PROMISING` | `QUALIFIED` |
| Hypothesis / inference | Fact |
| Marketing claim | Customer demand |
| One anecdote | Market-wide demand pattern |
| Google Trends 0–100 index | Absolute search volume or unit sales |
| Assumption | Supplier quote |
| Assumption | Margin figure |
| Assumption | Patent/IP clearance |
| Review count / BSR | Sales figure |

If information is missing, record `UNKNOWN` / `INSUFFICIENT_DATA` /
`INSUFFICIENTLY_OBSERVABLE` per `evidence-model.md` — never fill the gap with
a plausible-sounding number. If evidence conflicts, preserve **both** sides
and apply `evidence-model.md`'s contradiction rules — never quietly pick the
version that makes the candidate look better.

## Time and cost discipline

Cheap discovery and filtering must run — and eliminate weak candidates —
**before** any expensive step (live validation, competitor autopsy, browser
research, Google Trends requests, supplier/IP research). See
`time-budget-controller.md`. Never run `browser-brief` on a candidate below
`COMPETITOR_ANALYSIS` state — the engine itself refuses this, but a Skill
should never attempt it in the first place.

## What "improve the research layer" means here

Claude Browser (web search, Reddit, competitor sites) fills evidence gaps the
existing engine's providers structurally cannot — no automated provider in
this project has a live review-text API, for example (`provider-capability.md`).
This is real, additive capability. It must feed the *same* evidence tiers and
gates described above, at the `EXTERNAL_BROWSER_RESEARCH` (capped `ESTIMATE`)
or `HUMAN_VERIFIED` tier depending on who is asserting the observation —
never a new, looser tier invented to make browser findings feel more certain
than they are.

## Full rule set

The ~215 rules extracted from the source engine are indexed by domain in
`references/*.md`, each carrying source file:line and the test that pins its
behavior. The mapping from every extracted rule to its destination reference
is in `tests/rule-preservation/`.
