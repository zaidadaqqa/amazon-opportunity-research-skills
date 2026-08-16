# Browser Research Protocol — Methodology for Web/Reddit/Competitor Research

This is a methodology document, not a rule table with an ID/test mapping —
it governs *how* a Claude-driven browser research session should be
conducted, for anything that reads outside the deterministic engine's own
data (a live provider snapshot, a stored review, an engine-computed metric).
It underlies both the `browser-research` skill (external, non-Reddit-specific
research feeding `hunt browser-brief` / `browser-evidence-add`) and the
`reddit-voc` skill (`skills/reddit-voc/SKILL.md`, feeding `hunt voc-add` /
`hunt voc-manual-complete`). Both skills should treat this file as their
shared discipline layer.

The underlying reason this file exists: browser research is the one part of
this pipeline where a Skill, not deterministic Python, is doing the
information-gathering. Everything below exists to keep that gathering from
degrading into the exact hallucination failure modes the rest of this
system was built to prevent.

---

## 1. The seven fabrication prohibitions

These are restated, verbatim in substance, from the engine's own
`generate_browser_research_brief` (`src/engine/external_research/brief.py:34-42`)
— the same `PROHIBITIONS` list the engine embeds into every
`hunt browser-brief` prompt it generates. They apply to **all** browser
research a Skill performs, not only sessions launched via `browser-brief`:

1. **No fabricated statistics.** If a number wasn't actually seen on a real
   page, it does not appear in the findings — not even as a rounded
   "roughly" estimate.
2. **No invented search volume.** Browser research does not produce search
   volume numbers at all — that is Google Trends' job
   (`demand-intelligence.md`), and even Trends only ever yields a relative
   0–100 index, never absolute volume (see `core-rules.md`'s
   anti-hallucination table).
3. **No invented review sentiment.** Do not summarize "customers love this"
   or "customers hate this" without quoting/paraphrasing what was actually
   read, and do not infer sentiment from a star-rating percentage alone
   (the engine's own brief explicitly forbids this — `brief.py:138`).
4. **No treating a single anecdote as a market-wide trend.** One Reddit
   comment, one review, one forum post is `SINGLE_ANECDOTE`, not evidence
   of a pattern. See §3 below for the three-tier distinction to use
   instead.
5. **No treating affiliate/SEO content as primary evidence.** A listicle,
   a "10 best X" roundup, or an SEO-optimized comparison page is not a
   primary source for customer demand or sentiment — see the source-trust
   hierarchy in §2.
6. **No double-counting parent/child ASIN variants as separate
   competitors.** Same discipline as the engine's own `CMP-01` parent-ASIN
   dedup rule (`competition.md` §1.1) — a color/size variant of a listing
   already counted is not a second competitor.
7. **No unsupported claims of sales figures or profitability.** Browser
   research can report what a page/thread says about price, listed
   feature claims, or review counts as *observed*, but must never assert
   or imply how much a competitor is actually selling or earning.

Two closely related engine-brief requirements to carry into every finding,
not just the seven prohibitions above:
- Every claim must cite a real source URL. No source, no claim
  (`brief.py:136`).
- Do not infer customer sentiment from star-rating percentages alone
  (`brief.py:138`).

## 2. Source-trust hierarchy

Not all sources that pass the "real URL" bar in §1 carry equal weight. In
descending order of trust for a given type of claim:

1. **A direct customer complaint or praise, in the customer's own words**
   (a Reddit comment, a forum post, a review) — the strongest evidence for
   what a real user actually experienced or wants. This is what
   `reddit-voc` is built to find.
2. **A competitor's own product page / listing / documentation, for claims
   about that competitor's own product** — the competitor is the primary
   source for what their product does or costs; this is stronger than a
   third party's characterization of it.
3. **A third party's characterization of a competitor's claims** (a review
   site's summary of what a product does, a comparison article restating
   specs) — useful for triangulation, weaker than reading the primary page
   directly. Treat disagreements between this tier and tier 2 as a
   contradiction to preserve, not silently resolve in favor of the more
   convenient version.
4. **Affiliate/SEO listicle content** ("Top 10 Best X in 2026" pages
   optimized to rank and sell, not to inform) — lowest trust, and per §1
   prohibition 5, never usable as *primary* evidence for demand or
   sentiment. It may still be read to identify which competitors/products
   exist, but not as evidence of customer opinion.

When two sources conflict, keep **both** and note the conflict — do not
quietly prefer whichever version makes the candidate look more promising
(same contradiction-preservation discipline as `core-rules.md`'s
anti-hallucination contract).

## 3. Distinguishing a real pattern from noise

Use three tiers, matching the engine brief's own required distinction
(`brief.py:137`) — apply this to every problem/pattern claim before it goes
into a VOC finding or an evidence pack, not just to headline claims:

| Tier | Meaning | Minimum bar |
|---|---|---|
| `SINGLE_ANECDOTE` | One person, one instance | One source, one mention |
| `REPEATED_PATTERN` | The same complaint/praise shows up independently more than once | At least 2 distinct sources/threads/reviewers saying substantially the same thing, not the same post quoted twice |
| `STRONG_RECURRING_SIGNAL` | The complaint/praise is dominant across many independent sources | Enough independent recurrence that it would be misleading to call it niche |

This maps onto the VOC `frequency_signal` vocabulary
(`voc.md` §2: `ISOLATED` / `RECURRING` / `DOMINANT`) — do not mark
something `DOMINANT` (or `STRONG_RECURRING_SIGNAL`) from a single thread,
no matter how emphatically it was written.

## 4. Search discipline

- **Don't repeat the same query.** If a search returns the same handful of
  threads/pages already seen, vary the query (different phrasing, product
  category synonyms, complaint-specific terms) rather than re-running an
  identical search and treating repeated exposure to the same source as
  independent confirmation.
- **Don't treat one thread as representative of "Reddit says" or
  "customers say."** A single active thread with many replies is still one
  conversation, potentially dominated by a small number of vocal
  participants — check whether the same concern recurs across genuinely
  separate threads/subreddits/time periods before calling it a pattern.
- **Actively look for disconfirming evidence, not only supporting
  evidence.** After finding support for a hypothesis (e.g. "customers hate
  the current leading product's battery life"), deliberately search for
  counter-evidence (positive reviews mentioning the same attribute,
  competing products with the same complaint, evidence the complaint is
  tied to a specific batch/version rather than the product generally).
  Confirmation-seeking search behavior is exactly how a research session
  manufactures an illusion of demand or an illusion of a gap that isn't
  real — see `core-rules.md`'s anti-hallucination contract and
  `red-team.md`'s adversarial mandate, which this discipline directly
  feeds.
- Record what was searched and what was found, including negative results
  ("searched X, Y, Z — found nothing recurring") — a `voc-manual-complete
  --confirm-no-findings` call is only honest if a real search of this kind
  actually happened first (`voc.md` §5).

---

Source grounding: §1's seven prohibitions and the two extra requirements are
restated from `Amazon-products/src/engine/external_research/brief.py:34-42,
136-138` (the `PROHIBITIONS` tuple and adjacent `REQUIREMENTS` lines
embedded in every generated `hunt browser-brief`). §3's three-tier
distinction is the same `SINGLE_ANECDOTE` / `REPEATED_PATTERN` /
`STRONG_RECURRING_SIGNAL` language from `brief.py:137`. §2 and §4 are
research-discipline guidance for how a Skill should conduct the search
session itself; they are not separately enforced by engine code (nothing in
`Amazon-products` can verify a Skill actually searched broadly) — they exist
because `browser-evidence-add`/`voc-add` can only be as trustworthy as the
research that produced their inputs, and the engine has no way to check
that from the outside.
