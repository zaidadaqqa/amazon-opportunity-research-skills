# Red Team — Adversarial Analysis Rules

Canonical reference for the deterministic red-team layer
(`Amazon-products/src/engine/analysis/red_team.py`,
`llm/prompts/red_team_v1.md`), verified against source 2026-08-16. Applies
to `hunt redteam-prepare` / `redteam-submit`, the last automated stage
before `HUMAN_REVIEW`. The red team's job is to find reasons **not** to
build the business — not to reassure a Skill or a human that the candidate
is fine.

---

## 1. EVIDENCED vs HYPOTHESIS — downgrade, not drop (RT-01)

A red-team finding's `label` is `EVIDENCED` only if it cites at least one
`evidence_id` that survives validation. If a finding is *claimed* as
`EVIDENCED` but ends up with zero surviving evidence_ids after validation,
it is **downgraded to `HYPOTHESIS`** — it is kept, not dropped. Rationale
(from the source): "the underlying concern may still be worth a human's
attention even if the model mis-cited its source."

Source: `red_team.py:1-8`, `:66-73`.

### The three deliberately different anti-hallucination strategies

This is one of three domain-specific responses this system uses when a
claim's evidence citation fails validation — they are **intentionally
different**, not an inconsistency to "fix":

| Domain | Ungrounded claim outcome | Reference |
|---|---|---|
| VOC (pain points) | **Dropped entirely** — a pain point citing even one invalid evidence_id is discarded, no partial trust | `voc.md` §1 (VOC-01) |
| Differentiation (moat claims) | **Collapsed to `LOW_COPYCAT_RESISTANCE`**, `moat_categories=[]` — the claim is neutralized to the safest default, not removed | `differentiation.md` §2 (DIF-02) |
| Red team (risk findings) | **Downgraded to `HYPOTHESIS`** — the finding survives as a flag for human attention, just relabeled as unproven | this file, §1 (RT-01) |

The reasoning differs by what's at stake: a pain point that turns out
ungrounded shouldn't count as evidence of anything (dropping is safest); a
moat claim that turns out ungrounded shouldn't inflate ranking (collapsing
to the worst-case label is safest); a red-team risk that turns out
ungrounded might still be a real risk worth a human glancing at even
without a solid citation (keeping-but-relabeling is safest) — the
red-team's purpose is to surface concerns, and silently discarding an
unproven-but-plausible concern would work against that purpose. All three
share the same underlying principle (never let an ungrounded claim inflate
confidence) but apply it in the direction appropriate to that domain's risk.

## 2. Red-team scope checklist (RT-02, advisory/prompt-layer)

`llm/prompts/red_team_v1.md` instructs the model to consider — **only
where a plausible evidence connection actually exists**, never manufactured
speculatively:

- Demand illusion
- Seasonal illusion
- Temporary OOS (out-of-stock) illusion
- Review contamination
- Suspicious review patterns
- Margin illusion
- PPC (advertising) dependence
- Logistics problems
- Supplier problems
- IP/compliance risk
- Dominant incumbents
- Copycat vulnerability
- Stale/expired data
- Cross-source contradictions

Two explicit boundaries on this checklist, both from the prompt spec:
- Must **not** manufacture a risk with no plausible evidence connection —
  padding the findings list with generic boilerplate risk isn't the goal.
- Must **not** soften a well-evidenced negative finding to make the
  candidate look better.

This checklist is advisory at the prompt layer — there is no code-level
enforcement forcing every item to be addressed — but a Skill driving
`redteam-prepare`/`redteam-submit` should work through it deliberately
rather than stopping at the first plausible-sounding risk.

**The red team does not make the final accept/reject decision.** It
produces findings for a human to weigh at `HUMAN_REVIEW` — same as every
other automated stage in this pipeline, it stops short of `QUALIFIED` (see
`core-rules.md` rule 2).

### A red team that never finds anything is a signal, not a compliment

A clean red-team pass on one genuinely strong candidate is fine. A red-team
pass that suspiciously never surfaces *any* finding across many different
candidates is evidence the checklist isn't actually being applied — see
`skills/red-team/SKILL.md`.

Source: `llm/prompts/red_team_v1.md`.

---

## 3. Rule preservation

| Rule ID | This file's section | Source (Amazon-products file:line) | Test |
|---|---|---|---|
| RT-01 | 1 | red_team.py:1-8, :66-73 | test_evidenced_finding_with_valid_evidence_id_persists_as_evidenced, test_evidenced_finding_with_invalid_evidence_id_downgraded_to_hypothesis, test_hypothesis_labeled_finding_persists_unchanged, test_missing_tool_use_is_handled_without_crashing, test_verify_evidence_ids_exist_filters_correctly |
| RT-02 | 2 | llm/prompts/red_team_v1.md | (advisory/prompt-layer, no direct automated test) |
| VAL-01 | 1 (referenced) | evidence_validator.py:1-76 | (generic-walk validation suite; never repairs/invents evidence_ids) |
