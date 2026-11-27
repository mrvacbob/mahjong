"""Refresh the dependency-free subset of Mortal used by mj-rs."""
from pathlib import Path
import re
import shutil

root = Path(__file__).resolve().parent
upstream = root / "../../../3p/Mortal"
src = upstream / "libriichi/src"
out = root / "src"
algo = out / "algo"
(algo / "data").mkdir(parents=True, exist_ok=True)
shutil.copyfile(upstream / "LICENSE", root / "LICENSE.libriichi")
for file in (src / "algo/data").glob("*.gz"):
    shutil.copyfile(file, algo / "data" / file.name)
for name in ["macros", "tile"]:
    s = (src / f"{name}.rs").read_text()
    if name == "tile":
        s = s.replace("use ahash::AHashMap;", "use std::collections::HashMap;").replace("AHashMap", "HashMap")
        s = re.sub(r"use serde.*;\n", "", s)
        s = s[:s.index("impl<'de> Deserialize")] + s[s.index("impl fmt::Display for InvalidTile"):]
    (out / f"{name}.rs").write_text(s)
s = (src / "algo/shanten.rs").read_text().split("#[cfg(test)]")[0]
s = s.replace("use std::io::prelude::*;\n", "").replace("use flate2::read::GzDecoder;\n", "")
s = re.sub(r'include_bytes!\("data/(\w+\.bin)\.gz"\)', r'include_bytes!(concat!(env!("OUT_DIR"), "/\1"))', s)
s = re.sub(r"    let mut gz =.*?gz.read_to_end\(&mut raw\).unwrap\(\);\n", "", s, flags=re.S)
s = s.replace("gzipped: &[u8]", "raw: &[u8]").replace("raw.into_iter()", "raw.iter().copied()")
s = s[:s.index("#[must_use]\npub fn calc_all")]
(algo / "shanten.rs").write_text(s)
s = (src / "algo/agari.rs").read_text().split("#[cfg(test)]")[0]
s = s[:s.index("use boomphf")] + '''use std::collections::HashMap;
use std::io::{Cursor, Read};

static AGARI_TABLE: LazyLock<HashMap<u32, Vec<Div>>> = LazyLock::new(|| {
    let mut raw = Cursor::new(include_bytes!(concat!(env!("OUT_DIR"), "/agari.bin")));
    fn read_u32(raw: &mut impl Read) -> u32 {
        let mut buf = [0; 4];
        raw.read_exact(&mut buf).unwrap();
        u32::from_le_bytes(buf)
    }
    (0..9362).map(|_| {
        let key = read_u32(&mut raw);
        let mut size = [0];
        raw.read_exact(&mut size).unwrap();
        let values = (0..size[0]).map(|_| Div::from(read_u32(&mut raw))).collect();
        (key, values)
    }).collect()
});

''' + s[s.index("#[derive(Debug, Default)]"):]
s = s.replace("ArrayVec<[u8; 4]>", "Vec<u8>").replace("#[derive(Debug, Default)]", "#[derive(Clone, Debug, Default)]")
# Preserve the upstream division decoding and yaku predicates. Return the
# individual yaku for every winning tile placement.
s = s[:s.index("#[derive(Debug, Clone, Copy, Eq)]")] + s[s.index("pub struct AgariCalculator"):]
start = s.index("    /// Used in fu calc")
end = s.index("\n}", start)
s = s[:start] + "    placement: Placement," + s[end:]
s = s[:s.index("impl PartialEq for Agari")] + s[s.index("impl<'a> DivWorker"):]
start = s.index("        let mut ret = Self")
end = s.index("    /// The caller must assure", start)
s = s[:start] + '''        Self { sup: calc, tile14, div, pair_tile, menzen_kotsu, menzen_shuntsu, placement }
    }

    fn winning_tile_makes_minkou(&self) -> bool {
        self.sup.is_ron && self.placement == Placement::Triplet
    }

''' + s[end:]
s = s.replace("div: &'a Div) -> Self", "div: &'a Div, placement: Placement) -> Self")
s = s.replace("self.winning_tile_makes_minkou &&", "self.winning_tile_makes_minkou() &&")
s = s.replace("self.winning_tile_makes_minkou as usize", "self.winning_tile_makes_minkou() as usize")
start = s.index("        if !self.winning_tile_makes_minkou {")
end = s.index("        ((fu - 1)", start)
s = s[:start] + '''        if matches!(self.placement, Placement::Pair | Placement::BadSequence) {
            fu += 2;
        }

''' + s[end:]
start = s.index("    fn search_yakus<const")
end = s.index("        if has_pinfu", start)
s = s[:start] + '''    fn evaluate(&self) -> Evaluation {
        let mut yaku = vec![];
        let mut yakuman = vec![];
        let has_pinfu = self.menzen_shuntsu.len() == 4
            && !matches_tu8!(self.pair_tile, P | F | C)
            && self.pair_tile != self.sup.bakaze
            && self.pair_tile != self.sup.jikaze
            && self.placement == Placement::GoodSequence;

''' + s[end:]
start = s.index("        if has_pinfu {\n            //")
end = s.index("        make_return!();", start)
y = s[start:end]
names = iter([
    "pinfu", "chiitoi", "ryanpeikou", "chuuren", "tanyao", "toitoi", "tsuuiisou",
    'if has_jihai { "honitsu" } else { "chinitsu" }', "iipeikou", "iipeikou",
    "ittsu", "ittsu", "ittsu", "sanshoku", "sanshoku_doukou", "suuankou",
    "sanankou", "suukantsu", "sankantsu", "ryuuiisou", "yakuhai_round", "yakuhai_seat",
    "dragons", "daisangen", "shousangen", "daisuushii", "shousuushii", "honroutou",
    "chinroutou", 'if has_jihai { "chanta" } else { "junchan" }',
])
def tag(match):
    name = next(names)
    field, value = match.groups()
    if name == "dragons":
        return '''for (i, name) in ["yakuhai_haku", "yakuhai_hatsu", "yakuhai_chun"].into_iter().enumerate() {
                        if has_jihai[i + 4] { yaku.push((name, 1)); }
                    }'''
    if not name.startswith("if "):
        name = f'"{name}"'
    return f"{'yaku' if field == 'han' else field}.push(({name}, {value}))"
y = re.sub(r"check_early_return! \{ (han|yakuman) \+= (\w+) \}", tag, y)
assert next(names, None) is None
y = y.replace("if self.div.has_ipeikou {", "if self.sup.is_menzen && !self.div.has_ryanpeikou && self.div.has_ipeikou {")
y = y.replace("} else if !self.sup.ankans.is_empty()", "} else if !self.div.has_ryanpeikou && !self.sup.ankans.is_empty()")
s = s[:start] + y + '''        Evaluation { yaku, yakuman, fu: self.calc_fu(has_pinfu) }
    }
}

''' + s[s.index("fn get_tile14_and_key", end):s.index("/// `tehai` must")]
s = s.replace("use super::point::Point;\n", "").replace("use std::cmp::Ordering;\n", "").replace("use crate::tile::Tile;\n", "")
s = s.replace("tiles.chunks_exact(9)", "tiles.as_chunks::<9>().0.iter()")
(algo / "agari.rs").write_text(s + '\ninclude!("evaluation.rs");\n')

s = (src / "state/update.rs").read_text()
start = s.index("    pub(super) fn set_can_chi_from_tile")
end = s.index("    /// Can be called", start)
method = s[start:end].replace("pub(super) fn", "fn").replace("self.last_cans", "self.chi").replace("self.tehai", "self.concealed")
(out / "chi_candidates.rs").write_text(
    "// Adapted from Mortal libriichi state/update.rs. See LICENSE.libriichi.\n"
    "impl PlayerState<'_, '_> {\n" + method + "}\n"
)
