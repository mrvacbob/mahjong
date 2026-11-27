"""Line protocol of spec/formats.md: `<id> <op> key=value ...` -> `<id> key=value ...`."""

import sys
import traceback
from collections.abc import Callable

import hand as H
import legal as L
import scoring
from tiles import WIND_LETTERS, counts_of, format_kinds, meld_tiles, parse_melds, parse_tile, parse_tiles

type Args = dict[str, str]


def _context(a: Args) -> scoring.Context:
    flags = a.get("flags", "-")
    return scoring.Context(
        seat=WIND_LETTERS[a.get("seat", "E")],
        round=WIND_LETTERS[a.get("round", "E")],
        flags=frozenset() if flags == "-" else frozenset(flags.split(",")),
        dora=tuple(t.kind for t in parse_tiles(a.get("dora", "-"))),
        ura=tuple(t.kind for t in parse_tiles(a.get("ura", "-"))),
        honba=int(a.get("honba", "0")),
    )


def op_agari(a: Args) -> str:
    """The concealed tiles' forms; melds only shorten the hand, so they need not be read."""
    counts = counts_of(parse_tiles(a["hand"]))
    forms = [",".join(str(g) for g in f) for f in H.standard_forms(counts)]
    forms += [name for name, test in (("chiitoi", H.is_chiitoi), ("kokushi", H.is_kokushi)) if test(counts)]
    if not forms:
        return "win=0"
    return "win=1 forms=" + ";".join(sorted(forms))


def op_shanten(a: Args) -> str:
    counts = counts_of(parse_tiles(a["hand"]))
    s = H.shanten(counts, len(parse_melds(a.get("melds", "-"))))
    return f"std={s.std} chiitoi={_or_x(s.chiitoi)} kokushi={_or_x(s.kokushi)} min={s.min}"


def _or_x(n: int | None) -> str:
    return "x" if n is None else str(n)


def op_waits(a: Args) -> str:
    tiles = parse_tiles(a["hand"])
    melds = parse_melds(a.get("melds", "-"))
    visible = counts_of(tiles + meld_tiles(melds))
    w = H.waits(counts_of(tiles), len(melds), visible)
    return f"shanten={w.shanten} tiles={format_kinds(w.kinds)} count={w.count}"


def op_score(a: Args) -> str:
    r = scoring.best(parse_tiles(a["hand"]), parse_melds(a.get("melds", "-")),
                     parse_tile(a["win"]), a["by"] == "tsumo", _context(a))
    return f"error={r}" if isinstance(r, scoring.NoWin) else str(r)


def op_legal(a: Args) -> str:
    s = L.Situation(
        hand=parse_tiles(a["hand"]),
        melds=parse_melds(a.get("melds", "-")),
        ctx=_context(a),
        riichi=a.get("riichi") == "1",
        furiten=a.get("furiten") == "1",
        wall=int(a.get("wall", "70")),
        first=a.get("first") == "1",
        kans=int(a.get("kans", "0")),
    )
    if "draw" in a:
        acts = L.on_draw(s, parse_tile(a["draw"]))
    elif "discard" in a:
        acts = L.on_discard(s, parse_tile(a["discard"]), a["from"])
    elif "called" in a:
        acts = L.after_call(s, parse_melds(a["called"])[0], parse_tile(a["took"]))
    else:
        return "error=no_situation"
    return "actions=" + ",".join(sorted(set(acts)))


OPS: dict[str, Callable[[Args], str]] = {
    "agari": op_agari,
    "shanten": op_shanten,
    "waits": op_waits,
    "score": op_score,
    "legal": op_legal,
}


def answer(line: str) -> str:
    toks = line.split()
    if not toks:
        return ""
    rid = toks[0]
    try:
        op = OPS[toks[1]]
        args = dict(t.split("=", 1) for t in toks[2:])
        return f"{rid} {op(args)}"
    except (KeyError, ValueError, IndexError) as e:  # malformed request: unknown op, key or tile
        return f"{rid} error={type(e).__name__}"
    except Exception:  # a bug: answer, report it on stderr, keep serving
        traceback.print_exc()
        return f"{rid} error=internal"


def main() -> None:
    for line in sys.stdin:
        if resp := answer(line):
            print(resp, flush=True)


if __name__ == "__main__":
    main()
