# Brief: review the second batch of scenario tests

Same job as `Docs/Briefs/p3-F-review.md` (read it, and your own first review
`Docs/Reviews/p3/F-codex.md`), applied to the 69 scenarios added since: every file
in `Scenarios/` that your first review did not cover (`git log --diff-filter=A
--name-only -1 -- scenarios` on the latest scenario commit lists them).

For each: replay by hand, check tiles and turn order, every window answer present,
no accidental tenpai or callable tile in filler hands, no unintended furiten,
expectations right under `Spec/rules.md` for the stated ruleset, arithmetic redone,
and that it reaches the situation it claims. Fix clear errors directly, keep
`python3.14 Tools/scenario.py --check` passing, and record every change with
before, after and reasoning in `Docs/Reviews/p3/F2-codex.md`, plus anything you
believe is wrong but left, and whether the gaps from your first review are now
closed. Two notes: `rules.md` `extension_max_round` now states that a dealer repeat
in the extension's last hand continues play; and the writer says a dead-end pon and
a non-ron call on a fourth-riichi discard cannot occur in a legal game: confirm or
refute.

Do not read `Sources/` or `Tests/`. Touch only `Scenarios/` and your review file.
Do not commit.
