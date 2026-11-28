# Shootout formats and runner contract

Status: draft 2, revised after the Phase 1 council review
(`Docs/Reviews/p1/synthesis.md`). The body of this document is authoritative. The
Decisions log at the bottom is history; where it and the body differ, the body wins.

## Why plain text and not JSON

Mercury has no JSON in its standard library and this machine has GHC without cabal
(boot packages only). A line-oriented text format keeps the shootout about mahjong
and not about who has a JSON parser. The full engine (Phase 3) will speak mjai JSON.

## Runner contract

Each implementation builds one executable, `mj`.

- Reads requests from stdin, one per line. Writes one response line per request to
  stdout, in the same order. Exits 0 at EOF.
- Must not read the corpus's expected answers, the network, or anything under `3p/`.
- Standard library only: no third-party packages in any language (for Haskell,
  the packages that ship with GHC; for Swift, Foundation is allowed). Build tools
  such as SwiftPM, `mmc --make`, or cabal are fine.
- A request it cannot handle gets `<id> error=<reason>`, never a crash.
- Corpus requests are always well-formed and physically possible (tile lists in
  canonical order, at most four copies of a kind, at most one red five per suit,
  flag combinations that can occur). The only error answers the corpus expects are
  `error=not_agari` and `error=no_yaku` from `score`. What `mj` says for malformed
  input is not tested.

Request: `<id> <op> key=value key=value ...` (single spaces; values contain no spaces)
Response: `<id> key=value ...`

Keys in a response may come in any order. List values must be in the canonical
order given below, so the harness can compare strings.

Corpus files are `Corpus/<op>.txt`, two lines per case: the request, then the
expected response prefixed with `= `. Lines starting with `#` are comments.

## Tiles

mpsz notation. Suits `m` `p` `s`, digits 1–9. Honors are `z`: 1–4 = East South
West North, 5–7 = white, green, red (haku, hatsu, chun). A red five is digit `0`.

- A tile: `5m`, `0p`, `7z`.
- A tile list: digits grouped by suit, `123m406p77z`. Canonical order is m, p, s, z;
  within a suit ascending with `0` sorting immediately before `5`. Empty list is `-`.

Red fives behave as fives everywhere except: they count one aka dora each, and
they are distinct tiles in `legal` actions (`discard:0m` and `discard:5m` are
separate entries, likewise `riichi:` and `kakan:`).

Dora: the dora is the tile after the indicator, wrapping within its group:
9→1 in a suit, a red-five indicator counts as a 5 (dora is 6), winds
E→S→W→N→E, dragons white→green→red→white.

## Melds

`melds=` is a comma-separated list, or `-` for none. Each meld is a letter and its tiles:

| Form | Meaning |
|---|---|
| `c345m` | chi |
| `p777z` | pon |
| `k1111p` | open kan (daiminkan) |
| `s0555s` | added kan (shouminkan) |
| `a2222m` | closed kan (ankan) |

`hand=` never includes meld tiles. Closed kans are melds for shape purposes (they
can't be part of chiitoi or kokushi) but leave the hand closed for yaku and riichi. A hand with k melds has 13−3k tiles, or 14−3k
when it includes a drawn or winning tile (each op says which).

## Common context keys

| Key | Values | Default |
|---|---|---|
| `seat` | `E` `S` `W` `N` (seat wind) | `E` |
| `round` | `E` `S` `W` `N` (round wind) | `E` |
| `dora` | tile list of dora **indicators** | `-` |
| `ura` | tile list of ura dora indicators | `-` |
| `honba` | integer | `0` |
| `flags` | comma list, see `score` | `-` |
| `rules` | `mahjongsoul` or `tenhou`; `score` and `legal` only, see below | `mahjongsoul` |

## Ops

### `agari` — is this a complete hand, and how does it decompose

In: `hand` (14−3k tiles, including the winning tile), `melds`.
Out: `win=0` or `win=1 forms=<form>;<form>;...`

A form is one decomposition of the **concealed** tiles: comma-separated groups,
each a tile list, reds written as `5`. Groups within a form are sorted by suit
(m, p, s, z), then first digit, and for equal suit and first digit pair, then
sequence, then triplet. Forms are then sorted as plain strings, and forms that
print identically are listed once. Special forms: `chiitoi`, `kokushi`. A hand can have both
standard forms and `chiitoi` (ryanpeikou shapes); list all.

Example: `hand=11122233399m123p` →
`win=1 forms=111m,222m,333m,99m,123p;123m,123m,123m,99m,123p` (after sorting).

### `shanten`

In: `hand` (13−3k or 14−3k tiles), `melds`.
Out: `std=<n> chiitoi=<n> kokushi=<n> min=<n>`. −1 means complete. For a hand with
any meld, `chiitoi=x kokushi=x`. For a 14-tile hand, shanten is of the hand as it
stands (best discard assumed); a complete hand is −1.

Shanten is structural and ignores tile availability: `std` is
8 − 2·sets − partial sets − pair, with sets + partial sets ≤ 4. A hand whose only
wait is a fifth copy of a tile it holds four of (`234567789m1111z`) is tenpai,
`std=0`. Chiitoi needs seven distinct kinds: 6 − pairs + max(0, 7 − kinds).

### `waits`

In: `hand` (13−3k tiles), `melds`.
Out: `shanten=<n> tiles=<tile list> count=<n>`.

`tiles` are the tile kinds that lower `min` shanten when drawn (reds as `5`). A
kind is listed only if at least one copy is outside this hand and melds. `count`
is the total copies of listed kinds outside this hand and melds. A structurally
tenpai hand can therefore answer `shanten=0 tiles=- count=0`.

### `score`

In: `hand` (13−3k tiles, **excluding** the winning tile), `melds`, `win=<tile>`,
`by=tsumo|ron`, and context keys.

Flags: `riichi`, `double_riichi`, `ippatsu`, `haitei`, `houtei`, `rinshan`,
`chankan`, `tenhou`, `chiihou`. (`double_riichi` implies riichi; don't send both.)
Situational yaku come only from flags, never inferred from other keys. `ura` is
counted only with `riichi` or `double_riichi`, and ignored otherwise. `ippatsu`
can combine with `chankan` (a robbed kan was never completed, so it does not end
ippatsu).

Rulings that affect the answer:
- Ron on a shanpon wait makes the completed triplet open, for fu and for
  sanankou/suuankou. A tanki win on four concealed triplets is `suuankou_tanki` by
  ron or tsumo.
- `tenhou`: `hand` + `win` is the dealer's opening 14 tiles, and any of them may be
  treated as the winning tile; score the best choice (so tenhou with four concealed
  triplets is always `suuankou_tanki`, with kokushi always `kokushi_13`, with
  chuuren always `junsei_chuuren`). `chiihou` uses the supplied `win` tile.
- Kazoe yakuman (13+ han from ordinary yaku and dora) is answered in the ordinary
  form with its real han (`han=14 fu=30`), paid as one yakuman. It never uses the
  `yakuman=` key.
- Pao (liability) is out of scope: `score` answers the ordinary payment.

Out, one of:
- `error=not_agari` — not a complete hand.
- `error=no_yaku` — complete but no yaku (dora alone doesn't count).
- `yaku=<name:han,...> han=<n> fu=<n> pay=<pay> total=<n>` for ordinary hands.
- `yaku=<name:x,...> yakuman=<n> pay=<pay> total=<n>` for yakuman, where each
  yakuman is listed with the multiple it contributes (`:1`, or `:2` if the
  ruleset has double yakuman) and `yakuman` is the sum. No `han`/`fu`.

`yaku` is sorted by name. Dora appear in it as `dora:n`, `aka:n`, `ura:n` when n>0
and are included in `han`. Yaku from different decompositions never combine. The
interpretation with the highest `total` wins; ties go to a real yakuman over a
kazoe one, then higher han, then higher fu, then the yaku list that sorts first as
a string. (Between two real-yakuman interpretations there is no han or fu, so only
total and the string decide.)

`pay`:
- ron: `ron:<n>` — what the discarder pays, including honba (300 each).
- tsumo by dealer: `all:<n>` — what each other player pays, including honba (100 each).
- tsumo by non-dealer: `tsumo:<nondealer>/<dealer>` — including honba.

`total` is everything the winner receives from other players. Riichi sticks on the
table are not included.

Yaku names (fixed spelling): `riichi` `double_riichi` `ippatsu` `tsumo` `pinfu`
`tanyao` `iipeikou` `yakuhai_haku` `yakuhai_hatsu` `yakuhai_chun` `yakuhai_seat`
`yakuhai_round` `haitei` `houtei` `rinshan` `chankan` `chiitoi` `toitoi`
`sanankou` `sanshoku` `sanshoku_doukou` `ittsu` `chanta` `honroutou` `shousangen`
`sankantsu` `honitsu` `junchan` `ryanpeikou` `chinitsu`.

Yakuman names: `kokushi` `kokushi_13` `suuankou` `suuankou_tanki` `daisangen`
`shousuushii` `daisuushii` `tsuuiisou` `chinroutou` `ryuuiisou` `chuuren`
`junsei_chuuren` `suukantsu` `tenhou` `chiihou`.

Which of these are double, whether kazoe yakuman exists, kiriage mangan, and so on
come from `Spec/rules.md`. The corpus uses the default ruleset, Mahjong Soul.

`rules=tenhou` (added in Phase 3; `score` and `legal` only) answers under Tenhou
ranked rules instead. For `score` that changes two things: no yakuman is double, so
`kokushi_13`, `suuankou_tanki`, `junsei_chuuren` and `daisuushii` print `:1`; and
with `tenhou` the supplied `win` tile is the winning tile, with no free choice
among the 14 (so `kokushi`, not `kokushi_13`, when `win` is not the duplicate). For
`legal`, `flags=ankan_rob` never offers `ron` (Tenhou does not let kokushi rob a
closed kan). Any other value answers `error=bad_rules`. The Mercury cross-check
ignores this key and always answers Mahjong Soul.

### `legal` — what may this seat do right now

In: `hand`, `melds`, context keys, plus:

| Key | Meaning | Default |
|---|---|---|
| `draw=<tile>` | It is this seat's turn and it just drew this tile. `hand` excludes it. | |
| `discard=<tile>` + `from=kamicha\|toimen\|shimocha` | Another seat just discarded. (`kamicha` is the player to the left, whose discards can be chi'd.) | |
| `called=<meld>` + `took=<tile>` | This seat just called `took` to make this chi or pon (already in `melds`) and must now discard. The only actions are `discard:` entries: no riichi, kan or win. | |
| `riichi=0\|1` | This seat is already in riichi | `0` |
| `furiten=0\|1` | This seat is furiten (any kind) | `0` |
| `wall=<n>` | Live wall tiles remaining now (after the draw, if this is a draw) | `70` |
| `first=0\|1` | First uninterrupted go-around (no calls yet, seat hasn't discarded). Used only for `kyuushu`; it grants no yaku. | `0` |
| `kans=<n>` | Kans declared at the table so far, by anyone, this seat's included | `0` |

Exactly one of `draw`, `discard`, `called` is present. `hand` is 13−3k tiles in
the `draw` and `discard` cases and 14−3k in the `called` case (the new meld is
already in `melds`, counted in k, and the seat owes a discard).

Flags are the only source of situational yaku when deciding `tsumo` and `ron`;
`wall=0` on its own grants nothing. In the `draw` case `flags` may carry
`rinshan`, `haitei`, `tenhou` or `chiihou`; in the `discard` case `houtei`,
`chankan` or `ankan_rob`. A seat with `riichi=1` has the riichi yaku (the request
does not say whether ippatsu or double riichi apply; they aren't needed to decide
legality).

Robbing a kan: `discard=<tile> flags=chankan` means another seat is adding that
tile to a pon. `flags=ankan_rob` means another seat is declaring a closed kan of
that tile. In both cases the only possible actions are `ron` and `pass`. An added
kan can be robbed by any hand it completes (chankan is the yaku). A closed kan can
be robbed only by kokushi.

Tenpai, for `riichi:`: after the discard the hand has `shanten=0` **and** at least
one wait kind with a copy outside this hand and melds (the `waits` op would answer
`count>0`). A wait that exists only as a fifth copy doesn't qualify.

Kuikae, after a call, with `0` and `5` the same kind: after pon, the called kind
may not be discarded. After chi, the called kind may not be discarded, and if the
two tiles used from hand are adjacent and the tile at their other end exists, that
kind may not be discarded either (take 4 with 56: no 4, no 7; take 7 with 56: no
7, no 4; take 3 with 12: no 3; take 5 with 46: no 5).

Out: `actions=<comma list>`, sorted as strings. Never empty (`pass` or a discard always exists).

| Action | When |
|---|---|
| `discard:<tile>` | Own turn. One entry per distinct tile (red and non-red five are distinct). Includes the drawn tile. Kuikae-forbidden tiles are left out after a call. In riichi, only the drawn tile. |
| `riichi:<tile>` | Own turn, closed hand, not in riichi, discarding this tile leaves tenpai, `wall>=4`. (1000-point check is out of scope: assume enough points.) |
| `tsumo` | Own turn, hand complete with a yaku |
| `ankan:<kind>` | e.g. `ankan:5m`. `wall>=1`, `kans<4`. In riichi only when the kan uses the drawn tile and the set of wait kinds (structural, as in `shanten`) is the same before the draw and after the kan. The hand's decomposition may change. |
| `kakan:<tile>` | Add the exact tile to an existing pon. Same wall/kan limits. Never in riichi (a riichi hand has no pon). |
| `kyuushu` | `first=1`, own draw, nine or more distinct terminal/honor kinds |
| `ron` | Discard (or robbed kan tile) completes the hand with a yaku, and `furiten=0` |
| `chi:<two tiles>` | From `kamicha` only, e.g. on a 6m, `chi:45m` and, using the red, `chi:40m`. Not in riichi. `wall>=1`. Left out if every remaining discard would be kuikae. |
| `pon:<two tiles>` | e.g. `pon:55m` or `pon:05m`. Not in riichi. `wall>=1`. |
| `kan:<kind>` | Open kan on the discard. Not in riichi. `wall>=1`, `kans<4`. |
| `pass` | Always present when responding to a discard or a kan |

## Decisions log

History from the first corpus build. Superseded by the body above where they
differ; in particular: entry 3's 6x cap does not exist, entry 7's ties are now
decided by the tie-break and are in the corpus, entry 10's ban on ippatsu+chankan
is reversed, and entry 12 is replaced by the tenhou best-tile rule.

Entries by the Python-oracle corpus builder (Tools/, Corpus/*.txt except legal.txt).

1. **Spec fix (agari example).** The example listed groups in plain string order
   (`111m,123p,222m,...`), which contradicts the stated rule (suit, then first digit,
   then pair < sequence < triplet). The rule wins; the example now reads
   `111m,222m,333m,99m,123p;123m,123m,123m,99m,123p`. So `234m` precedes `222m`, and
   `22m` precedes `234m`. Forms are then sorted as plain strings.
2. **agari:** decompositions that print identically are listed once.
3. **Ruleset.** The brief's provisional assumptions (2-fu double-wind pair, no double
   yakuman) were replaced by Spec/rules.md (Mahjong Soul ranked) once it existed:
   double-wind pair = 4 fu; kokushi_13, suuankou_tanki, junsei_chuuren and daisuushii
   each print `:2`; distinct yakuman stack and `yakuman=` is the sum of the multiples
   (e.g. daisuushii:2 + suuankou_tanki:2 + tsuuiisou:1 = 5, paid as 5x). Kazoe stays 1x.
   Library settings used: open tanyao on, aka on, double yakuman on, kazoe limited to
   1x, kiriage off, open no-fu ron = 30 fu, pinfu tsumo = 20 fu, 6x yakuman cap. Score
   cases whose answer would differ under the old assumptions carry a
   `# rule-sensitive (...)` comment with the alternative answer (140 cases).
4. **Shanten ignores tile availability.** `std` is the textbook value
   8 - 2*sets - taatsu - head with sets+taatsu <= 4, so a hand waiting only on a fifth
   copy (e.g. `234567789m1111z`) is tenpai (std 0), and `waits` then lists nothing
   (`tiles=- count=0`), which is what the spec's waits rule implies. The oracle library
   instead adds Tenhou-style penalties for hands holding four of a kind and calls them
   1-shanten. Tools/oracle_mj.py uses its own search (checked against the library on
   every hand without a four-of-a-kind). Affected generated cases carry a
   `# rule-sensitive (oracle library's own 4-copy shanten)` note (16 shanten, 14 waits).
   See Corpus/disputed.txt.
5. **Chiitoi** needs seven distinct kinds. Four of a kind counts as one pair for both
   agari and chiitoi shanten (6 - pairs + max(0, 7 - kinds)).
6. **Kazoe yakuman** (13+ han from ordinary yaku and dora) prints in the ordinary form
   with its real han (`han=14 fu=30`) and is paid as a 1x yakuman. It never uses the
   `yakuman=` key.
7. **Ties the spec's tie-break cannot settle are left out of the corpus.** (a) A real
   yakuman and a kazoe interpretation with the same total (one case found:
   `hand=4477788999p melds=a1111p win=8p by=tsumo`, suuankou vs. chinitsu kazoe).
   "Higher han" means nothing for a yakuman. The library prefers the real yakuman, as
   Tenhou and Mahjong Soul display it. Suggest the spec say so. (b) Interpretations
   with equal total, han and fu that print different yaku lists: none found.
8. **ura** is counted only with `riichi` or `double_riichi`. Without them it is
   ignored. The generators only send `ura` with riichi.
9. **Red fives:** a request with more than one red of a suit, or with four non-red
   copies of a five, is invalid input (oracle_mj answers `error=bad_input`; the corpus
   never contains invalid input).
10. **Flag combinations** that cannot happen (riichi or ippatsu on an open hand;
   ippatsu without riichi; haitei/rinshan by ron; houtei/chankan by tsumo;
   haitei+rinshan; houtei+chankan; rinshan without a kan; ippatsu+rinshan; tenhou
   when not dealer, not tsumo or with melds; chiihou likewise) are never generated,
   and the response to them is unspecified. ippatsu+chankan is also never generated:
   the robbed added kan is a call, which ends ippatsu (Spec/rules.md, item 26).
   Generated chankan cases always have the winner holding no other copy of the
   winning tile.
11. **Ron on a shanpon** makes the completed triplet an open one, for fu and for
   sanankou/suuankou. A tanki win on four concealed triplets is suuankou_tanki by ron
   or by tsumo.
12. **tenhou/chiihou** take `hand` + `win` like any tsumo. The `win` tile still
   decides wait-dependent yakuman (kokushi vs kokushi_13, chuuren vs junsei_chuuren,
   suuankou vs suuankou_tanki). Whether Mahjong Soul upgrades these on a tenhou has
   not been checked.
13. **Dealer** is `seat=E`. Honba: +300 on ron, +100 per payer on tsumo (spec).
   Riichi sticks are never included.
14. **Dora indicator counts** in generated cases are realistic (1 + kans, sometimes one
   more) but no op checks the count.
15. **Errors beyond the spec's** (`error=bad_input`, `error=internal`,
   `error=unsupported` for `legal`) are oracle_mj's own; no corpus case expects them.
