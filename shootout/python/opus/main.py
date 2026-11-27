"""Line protocol of spec/formats.md: `<id> <op> key=value ...` -> `<id> key=value ...`."""

import sys
from collections.abc import Callable

import hand as H
import legal as L
import scoring
from tiles import WIND_LETTERS, counts_of, format_kinds, parse_melds, parse_tile, parse_tiles

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
    counts = counts_of(parse_tiles(a["hand"]))
    n_melds = len(parse_melds(a.get("melds", "-")))
    forms = [",".join(str(g) for g in f) for f in H.standard_forms(counts)]
    if not n_melds:
        if H.is_chiitoi(counts):
            forms.append("chiitoi")
        if H.is_kokushi(counts):
            forms.append("kokushi")
    if not forms:
        return "win=0"
    return "win=1 forms=" + ";".join(sorted(set(forms)))


def op_shanten(a: Args) -> str:
    counts = counts_of(parse_tiles(a["hand"]))
    s = H.shanten(counts, len(parse_melds(a.get("melds", "-"))))
    show = lambda n: "x" if n is None else str(n)  # noqa: E731
    return f"std={s.std} chiitoi={show(s.chiitoi)} kokushi={show(s.kokushi)} min={s.min}"


def op_waits(a: Args) -> str:
    tiles = parse_tiles(a["hand"])
    melds = parse_melds(a.get("melds", "-"))
    visible = counts_of(tiles + [t for m in melds for t in m.tiles])
    w = H.waits(counts_of(tiles), len(melds), visible)
    return f"shanten={w.shanten} tiles={format_kinds(w.kinds)} count={w.count}"


def op_score(a: Args) -> str:
    try:
        r = scoring.best(parse_tiles(a["hand"]), parse_melds(a.get("melds", "-")),
                         parse_tile(a["win"]), a["by"] == "tsumo", _context(a))
    except scoring.ScoreError as e:
        return f"error={e}"
    return str(r)


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
    except Exception as e:  # a request we can't handle must not crash the run
        return f"{rid} error={type(e).__name__}"


def main() -> None:
    out = sys.stdout
    for line in sys.stdin:
        resp = answer(line)
        if resp:
            out.write(resp + "\n")
            out.flush()


if __name__ == "__main__":
    main()
