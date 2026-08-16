---
name: ip-risk
description: use to research trademark/patent/design-patent risk for a promising candidate via legitimate public research (USPTO/trademark search, obvious brand conflicts), then record the result via hunt supplier-set --ip-status. Never claims legal clearance.
---

# IP Risk

Researches trademark/patent/design-patent risk for a candidate via
legitimate public research, then records the result via `hunt supplier-set
--ip-status`. Full vocabulary and human-origination rules live in
`references/supplier-ip.md`; read it before using this Skill.

**This Skill cannot, and must never claim to, provide legal clearance.**
That statement should be treated as load-bearing, not boilerplate — restate
it explicitly to the human every time this Skill's findings are presented.

## When to use this

For a promising candidate at `COMPETITOR_ANALYSIS` or later, before it
reaches `HUMAN_REVIEW` — IP risk should be surfaced before a human is asked
to make a final decision, not discovered after.

## Step 1 — Check what's already recorded

```
hunt supplier-show <opportunity_id>
```

Review the existing `ip_status`/`ip_notes` before starting new research
(`time-budget-controller.md` Rule 2).

## Step 2 — What legitimate research looks like

- **Public trademark databases** — e.g. USPTO's TESS/trademark search, or
  equivalent public registries for the target marketplace. Search for the
  candidate's likely brand name/product name and closely related terms.
- **Obvious existing-brand conflicts** — is this product a close copy of an
  already-branded, actively-sold product from an identifiable brand? A
  clearly obvious, undisputed conflict (e.g. reusing a well-known brand
  name or an unmistakably copied proprietary design) is a real finding
  worth flagging distinctly from an ordinary "many sellers in this
  category" observation.
- **Category-specific regulatory requirements** — e.g. FDA requirements for
  products with food/skin contact, CPSIA for children's products, or
  similar category-specific compliance obligations that are publicly
  documented requirements, not opinions. Note what's required, not whether
  the candidate would pass — that determination is out of scope for this
  Skill.

All of the above is public-record and public-search research — reading
public databases and product listings, not accessing anything
restricted or automating around access controls.

## Step 3 — What this Skill can conclude, and what it categorically cannot

Per `references/supplier-ip.md` SUP-01/IP-01, only these four literal
values are valid for `--ip-status`:

```
UNKNOWN | PENDING_HUMAN_LEGAL_REVIEW | CLEARED_BY_HUMAN | CONFIRMED_BLOCKER
```

This Skill's own research, by itself, can only ever justify recording:

- **`PENDING_HUMAN_LEGAL_REVIEW`** — the normal outcome for essentially all
  research this Skill performs, whether findings look concerning or not.
  This is the honest status for "meaningful IP/compliance verification is
  incomplete," per CLAUDE.md's IP/COMPLIANCE section, and it is what a
  competent, careful web search can actually support.
- **Flagging a genuinely obvious, undisputed conflict for human/lawyer
  confirmation of `CONFIRMED_BLOCKER`** — e.g. an unmistakable trademark
  reuse or an unmistakably copied proprietary design. This Skill should
  surface such a finding prominently and recommend the human treat it as
  serious, but it must not call `hunt supplier-set --ip-status
  CONFIRMED_BLOCKER` itself. Only after a human (ideally with legal
  judgment, or at minimum deliberate human confirmation) reviews and
  agrees should that status be recorded.
- **`CLEARED_BY_HUMAN`** — this Skill never records this status itself
  either; by definition it requires a human's own review and clearance,
  which this Skill cannot substitute for.

`CONFIRMED_BLOCKER` is the only IP status that fires the hard gate (IP-01)
— it must never be set from this Skill's own judgment alone, no matter how
confident the research makes the finding feel.

```
hunt supplier-set <opportunity_id> --ip-status PENDING_HUMAN_LEGAL_REVIEW \
  [--ip-notes "<summary of what was searched and found>"]
```

## Step 4 — Presenting findings

Always state plainly, in every findings summary:

- What was actually searched (which databases, which brand/product terms).
- What was found, including negative results ("no obvious trademark
  conflict found in TESS for [term]" — an absence-of-finding, not a
  clearance).
- That this research **does not constitute legal clearance** and a real
  IP-blocker finding needs a human, ideally a lawyer, to confirm
  `CONFIRMED_BLOCKER` before it can affect the candidate's standing.

## What this Skill must never do

- Never claim legal clearance for a product, under any phrasing.
- Never call `hunt supplier-set --ip-status CONFIRMED_BLOCKER` or
  `CLEARED_BY_HUMAN` from its own judgment alone — both require explicit
  human confirmation first.
- Never treat "I didn't find an obvious conflict" as equivalent to "cleared"
  — that is exactly `PENDING_HUMAN_LEGAL_REVIEW`, not `CLEARED_BY_HUMAN`.

See `references/supplier-ip.md` for the full vocabulary and the
rule-preservation table (SUP-01, IP-01 in particular).
