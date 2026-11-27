use crate::{algo::shanten, model::Counts};

pub fn standard(tiles: &Counts, groups: u8) -> i8 {
    if tiles.iter().any(|&n| n >= 4) {
        // Libriichi's lookup assumes a fifth copy cannot complete a shape.
        // For the wire-format shanten, count incomplete shapes structurally.
        // The waits operation applies its separate availability filter.
        let mut best = 2 * groups as i8;
        search(*tiles, groups, false, 0, &mut best);
        best
    } else {
        shanten::calc_normal(tiles, groups)
    }
}

fn search(tiles: Counts, groups: u8, head: bool, partial: u8, best: &mut i8) {
    let Some(i) = tiles.iter().position(|&n| n > 0) else {
        *best = (*best).min(2 * groups as i8 - groups.min(partial) as i8 - i8::from(head));
        return;
    };

    let take = |removed: &[usize], groups, head, partial, best: &mut i8| {
        let mut remaining = tiles;
        for &j in removed {
            remaining[j] -= 1;
        }
        search(remaining, groups, head, partial, best);
    };

    take(&[i], groups, head, partial, best);
    if tiles[i] >= 2 {
        if !head {
            take(&[i, i], groups, true, partial, best);
        }
        if partial < groups {
            take(&[i, i], groups, head, partial + 1, best);
        }
    }
    if groups > 0 && tiles[i] >= 3 {
        take(&[i, i, i], groups - 1, head, partial, best);
    }
    if i < 27 {
        let adjacent = i % 9 < 8 && tiles[i + 1] > 0;
        let gap = i % 9 < 7 && tiles[i + 2] > 0;
        if groups > 0 && adjacent && gap {
            take(&[i, i + 1, i + 2], groups - 1, head, partial, best);
        }
        if partial < groups {
            if adjacent {
                take(&[i, i + 1], groups, head, partial + 1, best);
            }
            if gap {
                take(&[i, i + 2], groups, head, partial + 1, best);
            }
        }
    }
}
