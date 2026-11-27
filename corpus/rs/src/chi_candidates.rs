// Adapted from Mortal libriichi state/update.rs. See LICENSE.libriichi.
impl PlayerState<'_, '_> {
    fn set_can_chi_from_tile(&mut self, tile: Tile) {
        self.chi.can_chi_low = false;
        self.chi.can_chi_mid = false;
        self.chi.can_chi_high = false;

        let tile_id = tile.deaka().as_usize();
        let literal_num = tile_id % 9 + 1;

        // it considered case like 1111234 where you cannot chi 14
        if literal_num <= 7 && self.concealed[tile_id + 1] > 0 && self.concealed[tile_id + 2] > 0 {
            // TODO: check the conditions only when self.shanten == 0?
            let mut tehai_after = self.concealed;
            tehai_after[tile_id] = 0;
            tehai_after[tile_id + 1] -= 1;
            tehai_after[tile_id + 2] -= 1;
            if literal_num < 7 {
                tehai_after[tile_id + 3] = 0;
            }
            self.chi.can_chi_low = tehai_after.iter().any(|&t| t > 0);
        }

        if matches!(literal_num, 2..=8)
            && self.concealed[tile_id - 1] > 0
            && self.concealed[tile_id + 1] > 0
        {
            let mut tehai_after = self.concealed;
            tehai_after[tile_id] = 0;
            tehai_after[tile_id - 1] -= 1;
            tehai_after[tile_id + 1] -= 1;
            self.chi.can_chi_mid = tehai_after.iter().any(|&t| t > 0);
        }

        if literal_num >= 3 && self.concealed[tile_id - 2] > 0 && self.concealed[tile_id - 1] > 0 {
            let mut tehai_after = self.concealed;
            tehai_after[tile_id] = 0;
            tehai_after[tile_id - 2] -= 1;
            tehai_after[tile_id - 1] -= 1;
            if literal_num > 3 {
                tehai_after[tile_id - 3] = 0;
            }
            self.chi.can_chi_high = tehai_after.iter().any(|&t| t > 0);
        }
    }

}
