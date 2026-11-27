import sys

from actions import legal
from scoring import Context, score
from shapes import Hand, Meld, agari, counts, parse_tile, parse_tiles, shanten, waits


def dispatch(op: str, args: dict[str, str]) -> str:
    raw_melds = args.get("melds", "-")
    melds = () if raw_melds == "-" else tuple(map(Meld.parse, raw_melds.split(",")))
    hand = Hand(parse_tiles(args["hand"]), melds)
    size = len(hand.tiles) + 3 * len(hand.melds)
    expected = (14,) if op == "agari" or (op == "legal" and "called" in args) else (13,)
    if op == "shanten":
        expected = (13, 14)
    if size not in expected or max(counts(hand.all_tiles())) > 4:
        raise ValueError("hand size or multiplicity")
    match op:
        case "agari":
            return agari(hand)
        case "shanten":
            return shanten(counts(hand.tiles), len(melds)).render()
        case "waits":
            return waits(hand)
        case "score":
            method = args["by"]
            if method not in {"ron", "tsumo"}:
                raise ValueError(method)
            win = parse_tile(args["win"])
            if max(counts((*hand.all_tiles(), win))) > 4:
                raise ValueError("winning tile multiplicity")
            result = score(hand, win, Context.parse(args, tsumo=method == "tsumo"))
            return result if isinstance(result, str) else result.render()
        case "legal":
            return legal(hand, args)
        case _:
            return "error=unsupported"


def main() -> None:
    for line in sys.stdin:
        parts = line.split()
        request_id = parts[0] if parts else "-"
        try:
            _, op, *fields = parts
            args = dict(field.split("=", 1) for field in fields)
            response = dispatch(op, args)
        except (ValueError, KeyError, IndexError):
            response = "error=bad_input"
        print(request_id, response, flush=True)


if __name__ == "__main__":
    main()
