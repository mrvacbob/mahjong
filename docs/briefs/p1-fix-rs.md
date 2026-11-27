# Brief: Phase 1 fixes — Rust reference and replay-derived legal corpus

Repo .. No git commands. Write only under
`agpl/mj-rs/` and `corpus/legal.txt`. Read `docs/reviews/p1/synthesis.md` and the
revised `spec/formats.md` (draft 2; the body is authoritative) first; the three
reviews in `docs/reviews/p1/` have the detail and derivations.

1. Bring `mj-rs` in line with formats.md draft 2:
   - riichi ankan: legal iff the kan uses the drawn tile and the structural wait
     kinds are unchanged; decomposition may change (legal0073–0078 become legal).
   - tenhou: score the best choice of winning tile among the 14; chiihou unchanged.
   - last-tile and other situational yaku in `legal` come only from flags; never
     infer haitei/houtei from `wall=0`. Accept `tenhou`/`chiihou` flags on a draw.
   - `flags=chankan` = robbed added kan: only ron/pass. New `flags=ankan_rob`:
     only ron/pass, ron only for kokushi.
   - riichi declaration needs a live wait (waits count > 0), written as its own
     rule rather than by reusing libriichi's penalised shanten.
   - tie-break order and everything else in the spec body.
2. Regenerate `corpus/legal.txt`: at most ~600 replay-derived cases, de-duplicated
   (no bulk suit permutations; pick for variety of situation), plus your directed
   cases. Every case at `wall=0` that is a last draw/discard must carry the
   `haitei`/`houtei` flag. Add directed cases for: ankan_rob (kokushi ron; ordinary
   hand gets pass only), okurikan in riichi (illegal), riichi seat able to tsumo
   and to ron, kan refused on the last draw, kyuushu with exactly 8 and 9 kinds,
   penchan chi and its kuikae discards, `called` snapshots with kan melds,
   daiminkan, furiten blocking ron.
3. Another agent is writing `corpus/legal_handwritten.txt` (complete action sets
   derived by hand, without your binary). When it exists, run it through `mj-rs`
   and write every disagreement to `agpl/mj-rs/DISAGREEMENTS.md` with your judgment.
   Do not edit that file's cases. Also rerun against the other corpus files (the
   other agent is regenerating score.txt for the tenhou and chankan+ippatsu
   changes) and replace the stale content of DISAGREEMENTS.md.

Report: what changed, case counts, remaining disagreements, anything in the
revised spec that is still ambiguous.
