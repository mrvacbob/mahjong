# Comparison with mj-rs

| Corpus | Compared | Disagreements |
| --- | ---: | ---: |
| `agari.txt` | 2179 | 0 |
| `disputed.txt` | 3 | 0 |
| `handwritten.txt` | 85 | 0 |
| `legal.txt` | 650 | 0 |
| `score.txt` | 5143 | 4 |
| `shanten.txt` | 2189 | 0 |
| `waits.txt` | 1984 | 0 |
| `smoke.txt` | 32 | 0 |
| `legal_handwritten.txt` | Missing | — |

The independently authored legal corpus was unavailable. The 85 cases in `handwritten.txt` were run and all passed.

## Score disagreements

The score corpus still uses the supplied tile for these four tenhou cases. Draft 2 maximizes the payment over the opening fourteen tiles. The Rust result follows draft 2 in each case.

~~~text
sc910 score hand=199m19p19s123467z melds=- win=5z by=tsumo seat=E round=S dora=3p honba=1 flags=tenhou
corpus  sc910 yaku=kokushi:1,tenhou:1 yakuman=2 pay=all:32100 total=96300
mj-rs   sc910 yaku=kokushi_13:2,tenhou:1 yakuman=3 pay=all:48100 total=144300
~~~

Choose the duplicated 9m as the winning tile. The remaining hand contains all thirteen orphans, so draft 2 awards double kokushi.

~~~text
sc918 score hand=44477m333p66s333z melds=- win=6s by=tsumo seat=E round=E dora=3m flags=tenhou
corpus  sc918 yaku=suuankou:1,tenhou:1 yakuman=2 pay=all:32000 total=96000
mj-rs   sc918 yaku=suuankou_tanki:2,tenhou:1 yakuman=3 pay=all:48000 total=144000
~~~

Choose 7m, the pair, as the winning tile. The four concealed triplets were already complete, so draft 2 awards suuankou tanki.

~~~text
sc3695 score hand=11p33377888s111z melds=- win=1p by=tsumo seat=E round=E dora=4s honba=1 flags=tenhou
corpus  sc3695 yaku=suuankou:1,tenhou:1 yakuman=2 pay=all:32100 total=96300
mj-rs   sc3695 yaku=suuankou_tanki:2,tenhou:1 yakuman=3 pay=all:48100 total=144300
~~~

Choose 7s, the pair, as the winning tile. This gives suuankou tanki, and one honba adds 100 per payer.

~~~text
sc5136 score hand=19m19p19s2345677z melds=- win=1z by=tsumo seat=E round=E flags=tenhou
corpus  sc5136 yaku=kokushi:1,tenhou:1 yakuman=2 pay=all:32000 total=96000
mj-rs   sc5136 yaku=kokushi_13:2,tenhou:1 yakuman=3 pay=all:48000 total=144000
~~~

Choose the duplicated 7z as the winning tile. That leaves all thirteen orphan kinds and gives double kokushi.
