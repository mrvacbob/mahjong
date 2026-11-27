# Brief: Phase 1 fixes — Python oracle, rules.md, hand-authored legal cases, harness

Repo .. No git commands. Write only under
`tools/`, `corpus/*.txt` except `corpus/legal.txt`, and `spec/rules.md`. Do not
touch `agpl/mj-rs/` or `spec/formats.md` (if formats.md is still wrong somewhere,
say so in your report). Read `docs/reviews/p1/synthesis.md` and the revised
`spec/formats.md` (draft 2; the body is authoritative) first; the three reviews in
`docs/reviews/p1/` have the detail and derivations.

1. `tools/oracle_mj.py` and generators: tenhou scores the best choice of winning
   tile (fix sc910, sc918, sc3695, sc5136 and add a tenhou chuuren case plus the
   matching chiihou cases); allow and generate ippatsu+chankan; add ura-without-riichi
   cases (ignored); a rinshan case where the 2 tsumo fu changes the rounding
   (codex.md finding 6 gives one); the real-yakuman-vs-kazoe tie from Decision 7;
   apply the spec's full tie-break. Regenerate; oracle self-test must be 100%.
2. `spec/rules.md`: fix item 26 and Unverified 5 (chankan + ippatsu combine), the
   garbled item 6 (use a correct pinfu-vs-fu example and verify it), §4.16 (ankan
   robbery is single-wait kokushi only), pao honba payer, the "highest han first"
   wording, riichi ankan wording (waits only), tenhou winning-tile rule, and source
   or remove the 6x cap. Keep the document's structure.
3. `corpus/legal_handwritten.txt`: at least 100 `legal` cases with the COMPLETE
   expected action set derived by hand from formats.md and rules.md. Do not run
   `mj-rs` or read `agpl/mj-rs/` or `corpus/legal.txt` to get answers; independence
   is the point of this file. Show the derivation in a `#` comment above each case.
   Cover every action type and every rule in the legal section: all three request
   kinds, riichi ankan (waits kept with decomposition changed; waits changed;
   okurikan), riichi needing a live wait, chankan and ankan_rob, kuikae for every
   chi shape and pon including reds, dead-end chi, haitei/houtei/rinshan/tenhou
   wins via flags and their absence at wall=0 without the flag, no-yaku hands that
   can't win, furiten, wall and kan limits, kyuushu at 8 and 9 kinds, riichi seat
   discarding only the drawn tile, kakan with red and non-red.
   After writing all of it, you may run it through
   `agpl/mj-rs/target/release/mj-rs` once it has been rebuilt by the other agent
   (it may not be ready; if so skip). Do not change your answers to match it:
   list disagreements in your report with your derivation.
4. `tools/harness.py`: if `mj` dies or times out mid-file, record that case as
   failed, restart the process, and continue with the next case.

Report: what changed, case counts, disagreements found, remaining spec problems.
