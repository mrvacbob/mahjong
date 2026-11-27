from itertools import combinations

from scoring import Context, Score, score
from shapes import (
    ORPHANS, Hand, Meld, Tiles, counts, kind, kokushi, parse_tile, tile_text,
    winning_kinds,
)


def discardable(tiles: Tiles, meld: Meld, took: int) -> set[int]:
    called_kind = kind(took)
    forbidden = {called_kind}
    if meld.call == "c":
        first = meld.group.first
        if called_kind == first and first % 9 < 6:
            forbidden.add(first + 3)
        if called_kind == first + 2 and first % 9 > 0:
            forbidden.add(first - 1)
    return {tile for tile in tiles if kind(tile) not in forbidden}


def without(tiles: Tiles, *used: int) -> Tiles:
    remaining = list(tiles)
    for tile in used:
        remaining.remove(tile)
    return tuple(remaining)


def on_draw(
    hand: Hand, drawn: int, ctx: Context, riichi: bool, wall: int, kans: int, first: bool,
) -> set[str]:
    full = (*hand.tiles, drawn)
    distinct = {drawn} if riichi else set(full)
    actions = {"discard:" + tile_text((tile,)) for tile in distinct}
    if isinstance(score(hand, drawn, ctx), Score):
        actions.add("tsumo")
    if first and len(ORPHANS.intersection(map(kind, full))) >= 9:
        actions.add("kyuushu")
    if not riichi and hand.closed and wall >= 4:
        for tile in distinct:
            after = Hand(without(full, tile), hand.melds)
            if next(winning_kinds(after), None) is not None:
                actions.add("riichi:" + tile_text((tile,)))
    if wall < 1 or kans >= 4:
        return actions
    for tile, n in enumerate(counts(full)):
        if n != 4:
            continue
        if riichi:
            if tile != kind(drawn):
                continue
            quad = tuple(t for t in full if kind(t) == tile)
            after = Hand(without(full, *quad), (*hand.melds, Meld("a", quad)))
            if set(winning_kinds(hand, structural=True)) != set(winning_kinds(after, structural=True)):
                continue
        actions.add("ankan:" + tile_text((tile,)))
    if not riichi:
        pons = {meld.group.first for meld in hand.melds if meld.call == "p"}
        actions.update("kakan:" + tile_text((tile,)) for tile in distinct if kind(tile) in pons)
    return actions


def on_discard(
    hand: Hand, taken: int, ctx: Context, riichi: bool, furiten: bool,
    wall: int, kans: int, from_left: bool,
) -> set[str]:
    actions = {"pass"}
    if not furiten:
        if "ankan_rob" in ctx.flags:
            if not hand.melds and kokushi(counts((*hand.tiles, taken))):
                actions.add("ron")
        elif isinstance(score(hand, taken, ctx), Score):
            actions.add("ron")
    if riichi or wall < 1 or ctx.flags & {"ankan_rob", "chankan"}:
        return actions
    called_kind = kind(taken)
    if kans < 4 and counts(hand.tiles)[called_kind] == 3:
        actions.add("kan:" + tile_text((called_kind,)))
    for pair in combinations(hand.tiles, 2):
        meld_kinds = sorted((called_kind, *map(kind, pair)))
        lo, mid, hi = meld_kinds
        if lo == hi:
            meld = Meld("p", (*pair, taken))
            action = "pon"
        elif from_left and lo // 9 == hi // 9 < 3 and mid == lo + 1 and hi == lo + 2:
            meld = Meld("c", (*pair, taken))
            action = "chi"
        else:
            continue
        if discardable(without(hand.tiles, *pair), meld, taken):
            actions.add(action + ":" + tile_text(pair))
    return actions


def legal(hand: Hand, args: dict[str, str]) -> str:
    riichi = args.get("riichi") == "1"
    wall = int(args.get("wall", "70"))
    kans = int(args.get("kans", "0"))
    if "called" in args:
        meld = Meld.parse(args["called"])
        took = parse_tile(args["took"])
        actions = {"discard:" + tile_text((t,)) for t in discardable(hand.tiles, meld, took)}
    elif "draw" in args:
        ctx = Context.parse(args, tsumo=True, riichi=riichi)
        actions = on_draw(hand, parse_tile(args["draw"]), ctx, riichi, wall, kans,
                          args.get("first") == "1")
    else:
        ctx = Context.parse(args, tsumo=False, riichi=riichi)
        actions = on_discard(hand, parse_tile(args["discard"]), ctx, riichi,
                             args.get("furiten") == "1", wall, kans, args["from"] == "kamicha")
    if not actions:
        raise ValueError("no actions")
    return "actions=" + ",".join(sorted(actions))
