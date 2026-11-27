# Shootout formats and runner contract

Status: draft 1. The corpus builders may tighten ambiguities they find; every such
decision gets a line in the "Decisions log" at the bottom.

## Why plain text and not JSON

Mercury has no JSON in its standard library and this machine has GHC without cabal
(boot packages only). A line-oriented text format keeps the shootout about mahjong
and not about who has a JSON parser. The full engine (Phase 3) will speak mjai JSON.

## Runner contract

Each implementation builds one executable, `mj`.

- Reads requests from stdin, one per line. Writes one response line per request to
  stdout, in the same order. Exits 0 at EOF.
- Must not read the corpus's expected answers, the network, or anything under `3p/`.
- A request it cannot handle gets `<id> error=<reason>`, never a crash.

Request: `<id> <op> key=value key=value ...` (single spaces; values contain no spaces)
Response: `<id> key=value ...`

Keys in a response may come in any order. List values must be in the canonical
order given below, so the harness can compare strings.

Corpus files are `corpus/<op>.txt`, two lines per case: the request, then the
expected response prefixed with `= `. Lines starting with `#` are comments.

## Tiles

mpsz notation. Suits `m` `p` `s`, digits 1–9. Honors are `z`: 1–4 = East South
West North, 5–7 = white, green, red (haku, hatsu, chun). A red five is digit `0`.

- A tile: `5m`, `0p`, `7z`.
- A tile list: digits grouped by suit, `123m406p77z`. Canonical order is m, p, s, z;
  within a suit ascending with `0` sorting immediately before `5`. Empty list is `-`.

Red fives behave as fives everywhere except: they count one aka dora each, and
they are distinct tiles in `legal` actions.

## Melds

`melds=` is a comma-separated list, or `-` for none. Each meld is a letter and its tiles:

| Form | Meaning |
|---|---|
| `c345m` | chi |
| `p777z` | pon |
| `k1111p` | open kan (daiminkan) |
| `s0555s` | added kan (shouminkan) |
| `a2222m` | closed kan (ankan) |

`hand=` never includes meld tiles. A hand with k melds has 13−3k tiles, or 14−3k
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

## Ops

### `agari` — is this a complete hand, and how does it decompose

In: `hand` (14−3k tiles, including the winning tile), `melds`.
Out: `win=0` or `win=1 forms=<form>;<form>;...`

A form is one decomposition of the **concealed** tiles: comma-separated groups,
each a tile list, reds written as `5`. Groups within a form sorted by suit
(m, p, s, z) then first digit then pairs before sequences before triplets; forms
sorted as strings. Special forms: `chiitoi`, `kokushi`. A hand can have both
standard forms and `chiitoi` (ryanpeikou shapes); list all.

Example: `hand=11122233399m123p` →
`win=1 forms=111m,123p,222m,333m,99m;123m,123m,123m,123p,99m` (after sorting).

### `shanten`

In: `hand` (13−3k or 14−3k tiles), `melds`.
Out: `std=<n> chiitoi=<n> kokushi=<n> min=<n>`. −1 means complete. For a hand with
any meld, `chiitoi=x kokushi=x`. For a 14-tile hand, shanten is of the hand as it
stands (best discard assumed).

### `waits`

In: `hand` (13−3k tiles), `melds`.
Out: `shanten=<n> tiles=<tile list> count=<n>`.

`tiles` are the tile kinds that lower `min` shanten when drawn (reds as `5`). A
kind is listed only if at least one copy is outside this hand and melds. `count`
is the total copies of listed kinds outside this hand and melds.

### `score`

In: `hand` (13−3k tiles, **excluding** the winning tile), `melds`, `win=<tile>`,
`by=tsumo|ron`, and context keys.

Flags: `riichi`, `double_riichi`, `ippatsu`, `haitei`, `houtei`, `rinshan`,
`chankan`, `tenhou`, `chiihou`. (`double_riichi` implies riichi; don't send both.)

Out, one of:
- `error=not_agari` — not a complete hand.
- `error=no_yaku` — complete but no yaku (dora alone doesn't count).
- `yaku=<name:han,...> han=<n> fu=<n> pay=<pay> total=<n>` for ordinary hands.
- `yaku=<name:x,...> yakuman=<n> pay=<pay> total=<n>` for yakuman, where each
  yakuman is listed with the multiple it contributes (`:1`, or `:2` if the
  ruleset has double yakuman) and `yakuman` is the sum. No `han`/`fu`.

`yaku` is sorted by name. Dora appear in it as `dora:n`, `aka:n`, `ura:n` when n>0
and are included in `han`. The interpretation with the highest `total` wins; ties
go to higher han, then higher fu.

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
come from `spec/rules.md`. The shootout uses one fixed ruleset (the default).

### `legal` — what may this seat do right now

In: `hand`, `melds`, context keys, plus:

| Key | Meaning | Default |
|---|---|---|
| `draw=<tile>` | It is this seat's turn and it just drew this tile. `hand` excludes it. | |
| `discard=<tile>` + `from=kamicha\|toimen\|shimocha` | Another seat just discarded. (`kamicha` is the player to the left, whose discards can be chi'd.) | |
| `called=<meld>` + `took=<tile>` | This seat just called `took` to make the meld (already in `melds`) and must now discard. | |
| `riichi=0\|1` | This seat is already in riichi | `0` |
| `furiten=0\|1` | This seat is furiten (any kind) | `0` |
| `wall=<n>` | Live wall tiles remaining | `70` |
| `first=0\|1` | First uninterrupted go-around (no calls yet, seat hasn't discarded) | `0` |
| `kans=<n>` | Kans declared at the table so far | `0` |

Exactly one of `draw`, `discard`, `called` is present. In the `draw` case,
`flags` may carry `rinshan` or `haitei`; in the `discard` case, `houtei` or `chankan`.

Out: `actions=<comma list>`, sorted as strings. Never empty (`pass` or a discard always exists).

| Action | When |
|---|---|
| `discard:<tile>` | Own turn. One entry per distinct tile (red and non-red five are distinct). Includes the drawn tile. Kuikae-forbidden tiles are left out after a call. In riichi, only the drawn tile. |
| `riichi:<tile>` | Own turn, closed hand, not in riichi, discarding this tile leaves tenpai, `wall>=4`. (1000-point check is out of scope: assume enough points.) |
| `tsumo` | Own turn, hand complete with a yaku |
| `ankan:<kind>` | e.g. `ankan:5m`. `wall>=1`, `kans<4`. In riichi only when it's the drawn tile and it changes neither waits nor hand interpretation. |
| `kakan:<tile>` | Add the exact tile to an existing pon. Same wall/kan limits. |
| `kyuushu` | `first=1`, own draw, nine or more distinct terminal/honor kinds |
| `ron` | Discard completes the hand with a yaku, and `furiten=0` |
| `chi:<two tiles>` | From `kamicha` only, e.g. `chi:46m`, `chi:40m` if a red is used. Not in riichi. `wall>=1`. Left out if every remaining discard would be kuikae. |
| `pon:<two tiles>` | e.g. `pon:55m` or `pon:05m`. Not in riichi. `wall>=1`. |
| `kan:<kind>` | Open kan on the discard. Not in riichi. `wall>=1`, `kans<4`. |
| `pass` | Always present when responding to a discard |

## Decisions log

(empty)
