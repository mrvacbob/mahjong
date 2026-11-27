# Comparison with the Python corpus

| Operation | Compared | Agreements | Disagreements |
| --- | ---: | ---: | ---: |
| agari | 2,179 | 2,179 | 0 |
| shanten | 2,189 | 2,189 | 0 |
| waits | 1,984 | 1,984 | 0 |
| score | 5,143 | 5,003 | 140 |

All 140 differences follow from two conflicts between the Python corpus brief’s provisional assumptions and the Mahjong Soul defaults in [spec/rules.md](../../spec/rules.md).

## Natural double yakuman (127)

The Rust answer follows the repository rules. Section 1 enables four natural doubles, and §2.2 lists each one explicitly. A qualifying yakuman contributes two multiples. When more than one occurs, add their multiples before computing the payments and add honba once.

~~~text
sc741 score hand=19m19p19s1234567z melds=- win=4z by=tsumo seat=S round=S dora=6m ura=4z honba=1 flags=riichi
Python  sc741 yaku=kokushi_13:1 yakuman=1 pay=tsumo:8100/16100 total=32300
Rust    sc741 yaku=kokushi_13:2 yakuman=2 pay=tsumo:16100/32100 total=64300
~~~

~~~text
sc742 score hand=19m19p19s1234567z melds=- win=1z by=tsumo seat=E round=E dora=6m
Python  sc742 yaku=kokushi_13:1 yakuman=1 pay=all:16000 total=48000
Rust    sc742 yaku=kokushi_13:2 yakuman=2 pay=all:32000 total=96000
~~~

~~~text
sc743 score hand=19m19p19s1234567z melds=- win=2z by=tsumo seat=N round=E dora=6m honba=2
Python  sc743 yaku=kokushi_13:1 yakuman=1 pay=tsumo:8200/16200 total=32600
Rust    sc743 yaku=kokushi_13:2 yakuman=2 pay=tsumo:16200/32200 total=64600
~~~

~~~text
sc744 score hand=19m19p19s1234567z melds=- win=1m by=ron seat=S round=E dora=9m2s honba=2
Python  sc744 yaku=kokushi_13:1 yakuman=1 pay=ron:32600 total=32600
Rust    sc744 yaku=kokushi_13:2 yakuman=2 pay=ron:64600 total=64600
~~~

~~~text
sc745 score hand=19m19p19s1234567z melds=- win=9s by=tsumo seat=W round=N dora=1m
Python  sc745 yaku=kokushi_13:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc745 yaku=kokushi_13:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc746 score hand=19m19p19s1234567z melds=- win=2z by=ron seat=E round=S dora=4s ura=6p honba=3 flags=riichi
Python  sc746 yaku=kokushi_13:1 yakuman=1 pay=ron:48900 total=48900
Rust    sc746 yaku=kokushi_13:2 yakuman=2 pay=ron:96900 total=96900
~~~

~~~text
sc747 score hand=19m19p19s1234567z melds=- win=4z by=ron seat=N round=E dora=2z flags=houtei
Python  sc747 yaku=kokushi_13:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc747 yaku=kokushi_13:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc748 score hand=19m19p19s1234567z melds=- win=2z by=ron seat=S round=E dora=2m
Python  sc748 yaku=kokushi_13:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc748 yaku=kokushi_13:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc749 score hand=19m19p19s1234567z melds=- win=1s by=tsumo seat=W round=E dora=2m ura=8m honba=1 flags=riichi
Python  sc749 yaku=kokushi_13:1 yakuman=1 pay=tsumo:8100/16100 total=32300
Rust    sc749 yaku=kokushi_13:2 yakuman=2 pay=tsumo:16100/32100 total=64300
~~~

~~~text
sc750 score hand=19m19p19s1234567z melds=- win=9m by=tsumo seat=W round=S dora=5p
Python  sc750 yaku=kokushi_13:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc750 yaku=kokushi_13:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc751 score hand=19m19p19s1234567z melds=- win=9p by=ron seat=W round=E dora=7p2s
Python  sc751 yaku=kokushi_13:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc751 yaku=kokushi_13:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc752 score hand=19m19p19s1234567z melds=- win=1s by=ron seat=N round=S dora=4s honba=2
Python  sc752 yaku=kokushi_13:1 yakuman=1 pay=ron:32600 total=32600
Rust    sc752 yaku=kokushi_13:2 yakuman=2 pay=ron:64600 total=64600
~~~

~~~text
sc753 score hand=19m19p19s1234567z melds=- win=9s by=ron seat=W round=E dora=1s honba=1
Python  sc753 yaku=kokushi_13:1 yakuman=1 pay=ron:32300 total=32300
Rust    sc753 yaku=kokushi_13:2 yakuman=2 pay=ron:64300 total=64300
~~~

~~~text
sc754 score hand=19m19p19s1234567z melds=- win=1s by=ron seat=N round=E dora=6p ura=5z flags=riichi
Python  sc754 yaku=kokushi_13:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc754 yaku=kokushi_13:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc769 score hand=055m055p1777s777z melds=- win=1s by=ron seat=E round=E dora=4s ura=4m flags=riichi
Python  sc769 yaku=suuankou_tanki:1 yakuman=1 pay=ron:48000 total=48000
Rust    sc769 yaku=suuankou_tanki:2 yakuman=2 pay=ron:96000 total=96000
~~~

~~~text
sc770 score hand=111666s2444555z melds=- win=2z by=tsumo seat=N round=N dora=1z
Python  sc770 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc770 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc771 score hand=444m2333888p888s melds=- win=2p by=ron seat=S round=E dora=1m honba=4
Python  sc771 yaku=suuankou_tanki:1 yakuman=1 pay=ron:33200 total=33200
Rust    sc771 yaku=suuankou_tanki:2 yakuman=2 pay=ron:65200 total=65200
~~~

~~~text
sc772 score hand=2223777p111s222z melds=- win=3p by=ron seat=W round=E dora=5z
Python  sc772 yaku=suuankou_tanki:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc772 yaku=suuankou_tanki:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc773 score hand=5m111p666999s111z melds=- win=5m by=ron seat=W round=E dora=6z
Python  sc773 yaku=suuankou_tanki:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc773 yaku=suuankou_tanki:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc774 score hand=1117p111666777s melds=- win=7p by=tsumo seat=W round=S dora=5m
Python  sc774 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc774 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc775 score hand=888m5p333s666z melds=a5555z win=0p by=ron seat=N round=E dora=2s7z
Python  sc775 yaku=suuankou_tanki:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc775 yaku=suuankou_tanki:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc776 score hand=6m444888p111s666z melds=- win=6m by=tsumo seat=W round=E dora=6z ura=5s flags=riichi
Python  sc776 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc776 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc777 score hand=222444m5p444666s melds=- win=0p by=ron seat=W round=E dora=2p ura=7s honba=1 flags=riichi
Python  sc777 yaku=suuankou_tanki:1 yakuman=1 pay=ron:32300 total=32300
Rust    sc777 yaku=suuankou_tanki:2 yakuman=2 pay=ron:64300 total=64300
~~~

~~~text
sc778 score hand=111777m777p7778s melds=- win=8s by=ron seat=W round=S dora=5s ura=4m flags=riichi,ippatsu
Python  sc778 yaku=suuankou_tanki:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc778 yaku=suuankou_tanki:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc779 score hand=1113m666p222555z melds=- win=3m by=ron seat=E round=S dora=2p honba=3
Python  sc779 yaku=suuankou_tanki:1 yakuman=1 pay=ron:48900 total=48900
Rust    sc779 yaku=suuankou_tanki:2 yakuman=2 pay=ron:96900 total=96900
~~~

~~~text
sc780 score hand=666888p888s5666z melds=- win=5z by=tsumo seat=W round=S dora=2m honba=1
Python  sc780 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8100/16100 total=32300
Rust    sc780 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16100/32100 total=64300
~~~

~~~text
sc781 score hand=777m777888s5557z melds=- win=7z by=tsumo seat=E round=S dora=1m
Python  sc781 yaku=suuankou_tanki:1 yakuman=1 pay=all:16000 total=48000
Rust    sc781 yaku=suuankou_tanki:2 yakuman=2 pay=all:32000 total=96000
~~~

~~~text
sc782 score hand=888m777p1113330s melds=- win=5s by=tsumo seat=E round=E dora=5m ura=8p honba=1 flags=riichi
Python  sc782 yaku=suuankou_tanki:1 yakuman=1 pay=all:16100 total=48300
Rust    sc782 yaku=suuankou_tanki:2 yakuman=2 pay=all:32100 total=96300
~~~

~~~text
sc811 score hand=66m22233444z melds=p111z win=3z by=ron seat=N round=S dora=1s
Python  sc811 yaku=daisuushii:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc811 yaku=daisuushii:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc812 score hand=44s11122233344z melds=- win=4z by=ron seat=E round=E dora=9m7z flags=houtei
Python  sc812 yaku=daisuushii:1 yakuman=1 pay=ron:48000 total=48000
Rust    sc812 yaku=daisuushii:2 yakuman=2 pay=ron:96000 total=96000
~~~

~~~text
sc813 score hand=05m11122233344z melds=- win=4z by=ron seat=W round=S dora=1p ura=5p flags=riichi
Python  sc813 yaku=daisuushii:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc813 yaku=daisuushii:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc814 score hand=33s11122233344z melds=- win=4z by=ron seat=W round=S dora=1p ura=2m honba=2 flags=riichi
Python  sc814 yaku=daisuushii:1 yakuman=1 pay=ron:32600 total=32600
Rust    sc814 yaku=daisuushii:2 yakuman=2 pay=ron:64600 total=64600
~~~

~~~text
sc815 score hand=1112223334455z melds=- win=4z by=ron seat=S round=E dora=7m ura=9m honba=4 flags=riichi
Python  sc815 yaku=daisuushii:1,tsuuiisou:1 yakuman=2 pay=ron:65200 total=65200
Rust    sc815 yaku=daisuushii:2,tsuuiisou:1 yakuman=3 pay=ron:97200 total=97200
~~~

~~~text
sc816 score hand=05s11222333z melds=s4444z win=1z by=tsumo seat=N round=W dora=8m2p flags=rinshan
Python  sc816 yaku=daisuushii:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc816 yaku=daisuushii:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc817 score hand=9m111222333444z melds=- win=9m by=ron seat=E round=E dora=6z ura=9p honba=2 flags=double_riichi
Python  sc817 yaku=daisuushii:1,suuankou_tanki:1 yakuman=2 pay=ron:96600 total=96600
Rust    sc817 yaku=daisuushii:2,suuankou_tanki:2 yakuman=4 pay=ron:192600 total=192600
~~~

~~~text
sc818 score hand=33m11122233344z melds=- win=4z by=ron seat=N round=E dora=8p ura=1p honba=1 flags=riichi
Python  sc818 yaku=daisuushii:1 yakuman=1 pay=ron:32300 total=32300
Rust    sc818 yaku=daisuushii:2 yakuman=2 pay=ron:64300 total=64300
~~~

~~~text
sc819 score hand=88m11122333444z melds=- win=2z by=tsumo seat=E round=W dora=3p
Python  sc819 yaku=daisuushii:1,suuankou:1 yakuman=2 pay=all:32000 total=96000
Rust    sc819 yaku=daisuushii:2,suuankou:1 yakuman=3 pay=all:48000 total=144000
~~~

~~~text
sc820 score hand=88p33444z melds=p111z,p222z win=3z by=ron seat=W round=E dora=6z honba=1
Python  sc820 yaku=daisuushii:1 yakuman=1 pay=ron:32300 total=32300
Rust    sc820 yaku=daisuushii:2 yakuman=2 pay=ron:64300 total=64300
~~~

~~~text
sc821 score hand=05p11122233z melds=p444z win=3z by=tsumo seat=N round=E dora=2m honba=4
Python  sc821 yaku=daisuushii:1 yakuman=1 pay=tsumo:8400/16400 total=33200
Rust    sc821 yaku=daisuushii:2 yakuman=2 pay=tsumo:16400/32400 total=65200
~~~

~~~text
sc822 score hand=6s111222333444z melds=- win=6s by=tsumo seat=W round=E dora=9p
Python  sc822 yaku=daisuushii:1,suuankou_tanki:1 yakuman=2 pay=tsumo:16000/32000 total=64000
Rust    sc822 yaku=daisuushii:2,suuankou_tanki:2 yakuman=4 pay=tsumo:32000/64000 total=128000
~~~

~~~text
sc823 score hand=44s11122244z melds=k3333z win=4z by=tsumo seat=W round=E dora=25z honba=1 flags=rinshan
Python  sc823 yaku=daisuushii:1 yakuman=1 pay=tsumo:8100/16100 total=32300
Rust    sc823 yaku=daisuushii:2 yakuman=2 pay=tsumo:16100/32100 total=64300
~~~

~~~text
sc824 score hand=7m111222333z melds=p444z win=7m by=ron seat=N round=E dora=4p
Python  sc824 yaku=daisuushii:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc824 yaku=daisuushii:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc831 score hand=4666777z melds=a1111z,a3333z win=4z by=ron seat=N round=E dora=2m36p ura=14m3s honba=2 flags=riichi,ippatsu
Python  sc831 yaku=suuankou_tanki:1,tsuuiisou:1 yakuman=2 pay=ron:64600 total=64600
Rust    sc831 yaku=suuankou_tanki:2,tsuuiisou:1 yakuman=3 pay=ron:96600 total=96600
~~~

~~~text
sc832 score hand=1112333444555z melds=- win=2z by=ron seat=S round=E dora=3s
Python  sc832 yaku=shousuushii:1,suuankou_tanki:1,tsuuiisou:1 yakuman=3 pay=ron:96000 total=96000
Rust    sc832 yaku=shousuushii:1,suuankou_tanki:2,tsuuiisou:1 yakuman=4 pay=ron:128000 total=128000
~~~

~~~text
sc839 score hand=111999m1119p999s melds=- win=9p by=ron seat=W round=E dora=3s honba=3
Python  sc839 yaku=chinroutou:1,suuankou_tanki:1 yakuman=2 pay=ron:64900 total=64900
Rust    sc839 yaku=chinroutou:1,suuankou_tanki:2 yakuman=3 pay=ron:96900 total=96900
~~~

~~~text
sc881 score hand=1112345678999m melds=- win=1m by=tsumo seat=N round=S dora=5z ura=9m honba=8 flags=riichi,ippatsu,haitei
Python  sc881 yaku=junsei_chuuren:1 yakuman=1 pay=tsumo:8800/16800 total=34400
Rust    sc881 yaku=junsei_chuuren:2 yakuman=2 pay=tsumo:16800/32800 total=66400
~~~

~~~text
sc882 score hand=1112345678999s melds=- win=7s by=tsumo seat=S round=E dora=4m
Python  sc882 yaku=junsei_chuuren:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc882 yaku=junsei_chuuren:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc883 score hand=1112345678999p melds=- win=4p by=ron seat=S round=E dora=5s ura=5m honba=1 flags=riichi
Python  sc883 yaku=junsei_chuuren:1 yakuman=1 pay=ron:32300 total=32300
Rust    sc883 yaku=junsei_chuuren:2 yakuman=2 pay=ron:64300 total=64300
~~~

~~~text
sc884 score hand=1112340678999m melds=- win=9m by=tsumo seat=W round=S dora=6z ura=4m honba=2 flags=riichi
Python  sc884 yaku=junsei_chuuren:1 yakuman=1 pay=tsumo:8200/16200 total=32600
Rust    sc884 yaku=junsei_chuuren:2 yakuman=2 pay=tsumo:16200/32200 total=64600
~~~

~~~text
sc885 score hand=1112345678999m melds=- win=9m by=tsumo seat=W round=S dora=3m
Python  sc885 yaku=junsei_chuuren:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc885 yaku=junsei_chuuren:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc886 score hand=1112345678999s melds=- win=7s by=ron seat=N round=E dora=6m
Python  sc886 yaku=junsei_chuuren:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc886 yaku=junsei_chuuren:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc887 score hand=1112340678999m melds=- win=1m by=ron seat=S round=E dora=1s ura=7s flags=riichi
Python  sc887 yaku=junsei_chuuren:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc887 yaku=junsei_chuuren:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc888 score hand=1112340678999s melds=- win=4s by=ron seat=E round=E dora=8m6p
Python  sc888 yaku=junsei_chuuren:1 yakuman=1 pay=ron:48000 total=48000
Rust    sc888 yaku=junsei_chuuren:2 yakuman=2 pay=ron:96000 total=96000
~~~

~~~text
sc889 score hand=1112345678999s melds=- win=3s by=ron seat=W round=W dora=7m ura=1m flags=riichi
Python  sc889 yaku=junsei_chuuren:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc889 yaku=junsei_chuuren:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc890 score hand=1112345678999p melds=- win=9p by=ron seat=S round=E dora=8m ura=2m flags=riichi
Python  sc890 yaku=junsei_chuuren:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc890 yaku=junsei_chuuren:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc891 score hand=1112345678999s melds=- win=0s by=ron seat=N round=E dora=9p3z ura=2m7z honba=2 flags=riichi
Python  sc891 yaku=junsei_chuuren:1 yakuman=1 pay=ron:32600 total=32600
Rust    sc891 yaku=junsei_chuuren:2 yakuman=2 pay=ron:64600 total=64600
~~~

~~~text
sc892 score hand=1112345678999s melds=- win=3s by=ron seat=N round=E dora=9p ura=2m flags=riichi
Python  sc892 yaku=junsei_chuuren:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc892 yaku=junsei_chuuren:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc893 score hand=1112345678999s melds=- win=8s by=ron seat=E round=S dora=4z ura=3z honba=1 flags=riichi
Python  sc893 yaku=junsei_chuuren:1 yakuman=1 pay=ron:48300 total=48300
Rust    sc893 yaku=junsei_chuuren:2 yakuman=2 pay=ron:96300 total=96300
~~~

~~~text
sc894 score hand=1112345678999m melds=- win=3m by=tsumo seat=S round=E dora=4s
Python  sc894 yaku=junsei_chuuren:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc894 yaku=junsei_chuuren:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc907 score hand=1z melds=a6666s,a2222m,a7777s,a3333z win=1z by=tsumo seat=E round=S dora=49m677p
Python  sc907 yaku=suuankou_tanki:1,suukantsu:1 yakuman=2 pay=all:32000 total=96000
Rust    sc907 yaku=suuankou_tanki:2,suukantsu:1 yakuman=3 pay=all:48000 total=144000
~~~

~~~text
sc1086 score hand=2s333z melds=a8888m,a8888p,a4444m win=2s by=ron seat=N round=E dora=23m2p5s honba=5
Python  sc1086 yaku=suuankou_tanki:1 yakuman=1 pay=ron:33500 total=33500
Rust    sc1086 yaku=suuankou_tanki:2 yakuman=2 pay=ron:65500 total=65500
~~~

~~~text
sc1100 score hand=222666p444055s3z melds=- win=3z by=tsumo seat=N round=E dora=7m ura=1s flags=riichi,ippatsu
Python  sc1100 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc1100 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc1306 score hand=444888m4777s777z melds=- win=4s by=tsumo seat=S round=N dora=6p
Python  sc1306 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc1306 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc1380 score hand=666p7z melds=a6666z,a6666m,a2222z win=7z by=ron seat=N round=E dora=3m15p1z ura=5m257s honba=1 flags=riichi
Python  sc1380 yaku=suuankou_tanki:1 yakuman=1 pay=ron:32300 total=32300
Rust    sc1380 yaku=suuankou_tanki:2 yakuman=2 pay=ron:64300 total=64300
~~~

~~~text
sc1901 score hand=19m19p19s1234567z melds=- win=7z by=ron seat=E round=E dora=9m ura=1s honba=5 flags=double_riichi
Python  sc1901 yaku=kokushi_13:1 yakuman=1 pay=ron:49500 total=49500
Rust    sc1901 yaku=kokushi_13:2 yakuman=2 pay=ron:97500 total=97500
~~~

~~~text
sc1931 score hand=055999m4446p111z melds=- win=6p by=tsumo seat=E round=E dora=1p ura=5z honba=1 flags=riichi
Python  sc1931 yaku=suuankou_tanki:1 yakuman=1 pay=all:16100 total=48300
Rust    sc1931 yaku=suuankou_tanki:2 yakuman=2 pay=all:32100 total=96300
~~~

~~~text
sc1962 score hand=7m melds=p222z,s3333z,p111z,p444z win=7m by=ron seat=S round=E dora=4p6z
Python  sc1962 yaku=daisuushii:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc1962 yaku=daisuushii:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc2032 score hand=111999p2333666z melds=- win=2z by=tsumo seat=S round=E dora=7s ura=1m honba=4 flags=riichi,ippatsu
Python  sc2032 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8400/16400 total=33200
Rust    sc2032 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16400/32400 total=65200
~~~

~~~text
sc2093 score hand=7m222p333777999s melds=- win=7m by=tsumo seat=W round=W dora=4m ura=6m flags=riichi,ippatsu
Python  sc2093 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc2093 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc2164 score hand=0m888p666s444555z melds=- win=5m by=tsumo seat=W round=S dora=8m
Python  sc2164 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc2164 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc2380 score hand=19m19p19s1234567z melds=- win=1m by=ron seat=E round=S dora=3p
Python  sc2380 yaku=kokushi_13:1 yakuman=1 pay=ron:48000 total=48000
Rust    sc2380 yaku=kokushi_13:2 yakuman=2 pay=ron:96000 total=96000
~~~

~~~text
sc2510 score hand=222444m2444p444s melds=- win=2p by=ron seat=E round=E dora=4z ura=9m honba=2 flags=riichi
Python  sc2510 yaku=suuankou_tanki:1 yakuman=1 pay=ron:48600 total=48600
Rust    sc2510 yaku=suuankou_tanki:2 yakuman=2 pay=ron:96600 total=96600
~~~

~~~text
sc2613 score hand=111555777m333p3z melds=- win=3z by=ron seat=S round=S dora=1m ura=6z flags=riichi
Python  sc2613 yaku=suuankou_tanki:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc2613 yaku=suuankou_tanki:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc2657 score hand=222m222333p222s1z melds=- win=1z by=ron seat=S round=E dora=6z ura=1s flags=double_riichi,ippatsu
Python  sc2657 yaku=suuankou_tanki:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc2657 yaku=suuankou_tanki:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc2814 score hand=2227m444s melds=a8888p,a7777s win=7m by=tsumo seat=W round=W dora=7p2s26z
Python  sc2814 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc2814 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc2873 score hand=111m222666p333s6z melds=- win=6z by=tsumo seat=S round=E dora=7m honba=1
Python  sc2873 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8100/16100 total=32300
Rust    sc2873 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16100/32100 total=64300
~~~

~~~text
sc2916 score hand=777m3336p055666s melds=- win=6p by=ron seat=S round=S dora=8m honba=1
Python  sc2916 yaku=suuankou_tanki:1 yakuman=1 pay=ron:32300 total=32300
Rust    sc2916 yaku=suuankou_tanki:2 yakuman=2 pay=ron:64300 total=64300
~~~

~~~text
sc2960 score hand=1112333m444888s melds=- win=2m by=tsumo seat=N round=W dora=9m ura=4m flags=double_riichi
Python  sc2960 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc2960 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc3084 score hand=1222333999m444p melds=- win=1m by=ron seat=E round=S dora=8m honba=2
Python  sc3084 yaku=suuankou_tanki:1 yakuman=1 pay=ron:48600 total=48600
Rust    sc3084 yaku=suuankou_tanki:2 yakuman=2 pay=ron:96600 total=96600
~~~

~~~text
sc3239 score hand=4z melds=a3333m,a1111p,a7777z,a4444s win=4z by=tsumo seat=S round=E dora=4m8p207s ura=8m5p23s3z flags=riichi
Python  sc3239 yaku=suuankou_tanki:1,suukantsu:1 yakuman=2 pay=tsumo:16000/32000 total=64000
Rust    sc3239 yaku=suuankou_tanki:2,suukantsu:1 yakuman=3 pay=tsumo:24000/48000 total=96000
~~~

~~~text
sc3242 score hand=444666m2224p111z melds=- win=4p by=tsumo seat=S round=N dora=6p ura=3s flags=riichi
Python  sc3242 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc3242 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc3275 score hand=6668p666s666777z melds=- win=8p by=tsumo seat=N round=S dora=1s ura=9s flags=riichi,ippatsu
Python  sc3275 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc3275 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc3377 score hand=9p999s333444777z melds=- win=9p by=ron seat=S round=S dora=1z
Python  sc3377 yaku=suuankou_tanki:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc3377 yaku=suuankou_tanki:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc3393 score hand=33m11122333444z melds=- win=2z by=ron seat=S round=E dora=7s honba=1
Python  sc3393 yaku=daisuushii:1 yakuman=1 pay=ron:32300 total=32300
Rust    sc3393 yaku=daisuushii:2 yakuman=2 pay=ron:64300 total=64300
~~~

~~~text
sc3498 score hand=999s2224z melds=a3333z,a1111z win=4z by=tsumo seat=S round=E dora=1m6p7s ura=6m26z flags=riichi
Python  sc3498 yaku=shousuushii:1,suuankou_tanki:1 yakuman=2 pay=tsumo:16000/32000 total=64000
Rust    sc3498 yaku=shousuushii:1,suuankou_tanki:2 yakuman=3 pay=tsumo:24000/48000 total=96000
~~~

~~~text
sc3604 score hand=777m777p777888s1z melds=- win=1z by=tsumo seat=N round=S dora=3m
Python  sc3604 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc3604 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc3722 score hand=6m222333z melds=p444z,p111z win=6m by=ron seat=S round=E dora=3m
Python  sc3722 yaku=daisuushii:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc3722 yaku=daisuushii:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc3827 score hand=1112233344455z melds=- win=2z by=tsumo seat=S round=E dora=2m ura=2m honba=2 flags=double_riichi
Python  sc3827 yaku=daisuushii:1,suuankou:1,tsuuiisou:1 yakuman=3 pay=tsumo:24200/48200 total=96600
Rust    sc3827 yaku=daisuushii:2,suuankou:1,tsuuiisou:1 yakuman=4 pay=tsumo:32200/64200 total=128600
~~~

~~~text
sc3861 score hand=1m111222333666z melds=- win=1m by=tsumo seat=N round=S dora=1p
Python  sc3861 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc3861 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc4051 score hand=222444m9p777s666z melds=- win=9p by=ron seat=S round=E dora=6p honba=1 flags=houtei
Python  sc4051 yaku=suuankou_tanki:1 yakuman=1 pay=ron:32300 total=32300
Rust    sc4051 yaku=suuankou_tanki:2 yakuman=2 pay=ron:64300 total=64300
~~~

~~~text
sc4365 score hand=333m2223338p333s melds=- win=8p by=ron seat=E round=E dora=3z ura=7z flags=riichi
Python  sc4365 yaku=suuankou_tanki:1 yakuman=1 pay=ron:48000 total=48000
Rust    sc4365 yaku=suuankou_tanki:2 yakuman=2 pay=ron:96000 total=96000
~~~

~~~text
sc4403 score hand=3m melds=a2222p,a2222m,a9999p,a1111z win=3m by=tsumo seat=S round=E dora=5m3p68s7z ura=3m3p3s24z flags=riichi,ippatsu
Python  sc4403 yaku=suuankou_tanki:1,suukantsu:1 yakuman=2 pay=tsumo:16000/32000 total=64000
Rust    sc4403 yaku=suuankou_tanki:2,suukantsu:1 yakuman=3 pay=tsumo:24000/48000 total=96000
~~~

~~~text
sc4464 score hand=33s33344z melds=p222z,k1111z win=4z by=tsumo seat=E round=W dora=4m3s honba=2
Python  sc4464 yaku=daisuushii:1 yakuman=1 pay=all:16200 total=48600
Rust    sc4464 yaku=daisuushii:2 yakuman=2 pay=all:32200 total=96600
~~~

~~~text
sc4505 score hand=3337m666777p555z melds=- win=7m by=ron seat=E round=E dora=2s
Python  sc4505 yaku=suuankou_tanki:1 yakuman=1 pay=ron:48000 total=48000
Rust    sc4505 yaku=suuankou_tanki:2 yakuman=2 pay=ron:96000 total=96000
~~~

~~~text
sc4509 score hand=111m4s222666777z melds=- win=4s by=ron seat=S round=E dora=9m ura=9p flags=riichi
Python  sc4509 yaku=suuankou_tanki:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc4509 yaku=suuankou_tanki:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc4537 score hand=333444m055p3334z melds=- win=4z by=tsumo seat=S round=N dora=6p honba=2
Python  sc4537 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8200/16200 total=32600
Rust    sc4537 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16200/32200 total=64600
~~~

~~~text
sc4547 score hand=1115666m888s melds=a1111s win=0m by=ron seat=E round=E dora=6p2s
Python  sc4547 yaku=suuankou_tanki:1 yakuman=1 pay=ron:48000 total=48000
Rust    sc4547 yaku=suuankou_tanki:2 yakuman=2 pay=ron:96000 total=96000
~~~

~~~text
sc4616 score hand=222m444s1115557z melds=- win=7z by=tsumo seat=E round=E dora=8p honba=3
Python  sc4616 yaku=suuankou_tanki:1 yakuman=1 pay=all:16300 total=48900
Rust    sc4616 yaku=suuankou_tanki:2 yakuman=2 pay=all:32300 total=96900
~~~

~~~text
sc4744 score hand=111m1222444p111s melds=- win=1p by=ron seat=E round=E dora=2s
Python  sc4744 yaku=suuankou_tanki:1 yakuman=1 pay=ron:48000 total=48000
Rust    sc4744 yaku=suuankou_tanki:2 yakuman=2 pay=ron:96000 total=96000
~~~

~~~text
sc4869 score hand=2223337z melds=p111z,p444z win=7z by=ron seat=E round=E dora=1p7z honba=4
Python  sc4869 yaku=daisuushii:1,tsuuiisou:1 yakuman=2 pay=ron:97200 total=97200
Rust    sc4869 yaku=daisuushii:2,tsuuiisou:1 yakuman=3 pay=ron:145200 total=145200
~~~

~~~text
sc4874 score hand=444m8p666s333777z melds=- win=8p by=ron seat=N round=S dora=7s2z
Python  sc4874 yaku=suuankou_tanki:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc4874 yaku=suuankou_tanki:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc4934 score hand=19m19p19s1234567z melds=- win=6z by=tsumo seat=S round=E dora=6p2z
Python  sc4934 yaku=kokushi_13:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc4934 yaku=kokushi_13:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc4970 score hand=444m055p3444777s melds=- win=3s by=tsumo seat=W round=E dora=3p
Python  sc4970 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc4970 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc4987 score hand=19m19p19s1234567z melds=- win=1s by=ron seat=E round=E
Python  sc4987 yaku=kokushi_13:1 yakuman=1 pay=ron:48000 total=48000
Rust    sc4987 yaku=kokushi_13:2 yakuman=2 pay=ron:96000 total=96000
~~~

~~~text
sc4990 score hand=3z melds=a1111z,a5555z,a6666z,a7777z win=3z by=tsumo seat=E round=E dora=22224444z flags=riichi,ippatsu,haitei
Python  sc4990 yaku=daisangen:1,suuankou_tanki:1,suukantsu:1,tsuuiisou:1 yakuman=4 pay=all:64000 total=192000
Rust    sc4990 yaku=daisangen:1,suuankou_tanki:2,suukantsu:1,tsuuiisou:1 yakuman=5 pay=all:80000 total=240000
~~~

~~~text
sc4993 score hand=11s11122333z melds=p444z win=2z by=tsumo seat=E round=E
Python  sc4993 yaku=daisuushii:1 yakuman=1 pay=all:16000 total=48000
Rust    sc4993 yaku=daisuushii:2 yakuman=2 pay=all:32000 total=96000
~~~

~~~text
sc4995 score hand=1113335556668m melds=- win=8m by=tsumo seat=E round=E
Python  sc4995 yaku=suuankou_tanki:1 yakuman=1 pay=all:16000 total=48000
Rust    sc4995 yaku=suuankou_tanki:2 yakuman=2 pay=all:32000 total=96000
~~~

~~~text
sc4997 score hand=1112345678999m melds=- win=1m by=tsumo seat=E round=E
Python  sc4997 yaku=junsei_chuuren:1 yakuman=1 pay=all:16000 total=48000
Rust    sc4997 yaku=junsei_chuuren:2 yakuman=2 pay=all:32000 total=96000
~~~

~~~text
sc4998 score hand=1112345678999m melds=- win=5m by=tsumo seat=E round=E
Python  sc4998 yaku=junsei_chuuren:1 yakuman=1 pay=all:16000 total=48000
Rust    sc4998 yaku=junsei_chuuren:2 yakuman=2 pay=all:32000 total=96000
~~~

~~~text
sc5003 score hand=1112223334445z melds=- win=5z by=ron seat=E round=E
Python  sc5003 yaku=daisuushii:1,suuankou_tanki:1,tsuuiisou:1 yakuman=3 pay=ron:144000 total=144000
Rust    sc5003 yaku=daisuushii:2,suuankou_tanki:2,tsuuiisou:1 yakuman=5 pay=ron:240000 total=240000
~~~

~~~text
sc5004 score hand=111999m111999p1s melds=- win=1s by=tsumo seat=E round=E
Python  sc5004 yaku=chinroutou:1,suuankou_tanki:1 yakuman=2 pay=all:32000 total=96000
Rust    sc5004 yaku=chinroutou:1,suuankou_tanki:2 yakuman=3 pay=all:48000 total=144000
~~~

~~~text
sc5005 score hand=19m19p19s1234567z melds=- win=7z by=tsumo seat=E round=E
Python  sc5005 yaku=kokushi_13:1 yakuman=1 pay=all:16000 total=48000
Rust    sc5005 yaku=kokushi_13:2 yakuman=2 pay=all:32000 total=96000
~~~

~~~text
sc5006 score hand=19m19p19s1234567z melds=- win=7z by=ron seat=E round=E dora=8m
Python  sc5006 yaku=kokushi_13:1 yakuman=1 pay=ron:48000 total=48000
Rust    sc5006 yaku=kokushi_13:2 yakuman=2 pay=ron:96000 total=96000
~~~

~~~text
sc5007 score hand=19m19p19s1234567z melds=- win=7z by=ron seat=E round=E ura=8m flags=riichi
Python  sc5007 yaku=kokushi_13:1 yakuman=1 pay=ron:48000 total=48000
Rust    sc5007 yaku=kokushi_13:2 yakuman=2 pay=ron:96000 total=96000
~~~

~~~text
sc5118 score hand=22s11122233344z melds=- win=4z by=ron seat=S round=E
Python  sc5118 yaku=daisuushii:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc5118 yaku=daisuushii:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc5120 score hand=111999m9p111222s melds=- win=9p by=ron seat=S round=E
Python  sc5120 yaku=suuankou_tanki:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc5120 yaku=suuankou_tanki:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc5122 score hand=19m19p19s1234567z melds=- win=1s by=ron seat=S round=E
Python  sc5122 yaku=kokushi_13:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc5122 yaku=kokushi_13:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc5126 score hand=333m4445p111444s melds=- win=5p by=tsumo seat=S round=E
Python  sc5126 yaku=suuankou_tanki:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc5126 yaku=suuankou_tanki:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc5127 score hand=3334445557779m melds=- win=9m by=ron seat=S round=E
Python  sc5127 yaku=suuankou_tanki:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc5127 yaku=suuankou_tanki:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc5129 score hand=1112345678999m melds=- win=2m by=ron seat=S round=E
Python  sc5129 yaku=junsei_chuuren:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc5129 yaku=junsei_chuuren:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc5130 score hand=1112345678999m melds=- win=9m by=ron seat=S round=E
Python  sc5130 yaku=junsei_chuuren:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc5130 yaku=junsei_chuuren:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc5131 score hand=1112345678999m melds=- win=1m by=ron seat=S round=E
Python  sc5131 yaku=junsei_chuuren:1 yakuman=1 pay=ron:32000 total=32000
Rust    sc5131 yaku=junsei_chuuren:2 yakuman=2 pay=ron:64000 total=64000
~~~

~~~text
sc5133 score hand=1112223334445z melds=- win=5z by=tsumo seat=E round=E flags=tenhou
Python  sc5133 yaku=daisuushii:1,suuankou_tanki:1,tenhou:1,tsuuiisou:1 yakuman=4 pay=all:64000 total=192000
Rust    sc5133 yaku=daisuushii:2,suuankou_tanki:2,tenhou:1,tsuuiisou:1 yakuman=6 pay=all:96000 total=288000
~~~

~~~text
sc5134 score hand=5z melds=a1111z,a2222z,a3333z,a4444z win=5z by=ron seat=S round=E
Python  sc5134 yaku=daisuushii:1,suuankou_tanki:1,suukantsu:1,tsuuiisou:1 yakuman=4 pay=ron:128000 total=128000
Rust    sc5134 yaku=daisuushii:2,suuankou_tanki:2,suukantsu:1,tsuuiisou:1 yakuman=6 pay=ron:192000 total=192000
~~~

~~~text
sc5138 score hand=19m19p19s1234567z melds=- win=7z by=tsumo seat=S round=E
Python  sc5138 yaku=kokushi_13:1 yakuman=1 pay=tsumo:8000/16000 total=32000
Rust    sc5138 yaku=kokushi_13:2 yakuman=2 pay=tsumo:16000/32000 total=64000
~~~

~~~text
sc5139 score hand=19m19p19s1234567z melds=- win=7z by=tsumo seat=E round=E flags=tenhou
Python  sc5139 yaku=kokushi_13:1,tenhou:1 yakuman=2 pay=all:32000 total=96000
Rust    sc5139 yaku=kokushi_13:2,tenhou:1 yakuman=3 pay=all:48000 total=144000
~~~

~~~text
sc5140 score hand=19m19p19s1234567z melds=- win=7z by=tsumo seat=S round=E flags=chiihou
Python  sc5140 yaku=chiihou:1,kokushi_13:1 yakuman=2 pay=tsumo:16000/32000 total=64000
Rust    sc5140 yaku=chiihou:1,kokushi_13:2 yakuman=3 pay=tsumo:24000/48000 total=96000
~~~
## Double-wind pair fu (13)

The Rust answer follows the repository rules. Section 3.1 gives the pair four fu when the same wind is both seat and round wind. The Python oracle’s provisional rule gives two. In each row below, that difference crosses a rounding boundary and raises the hand by ten fu. Payments change where the higher fu affects basic points.

~~~text
sc200 score hand=1z melds=s2222z,p444s,p777z,p444z win=1z by=ron seat=E round=E dora=5p3s honba=1
Python  sc200 yaku=dora:3,honitsu:2,toitoi:2,yakuhai_chun:1 han=8 fu=50 pay=ron:24300 total=24300
Rust    sc200 yaku=dora:3,honitsu:2,toitoi:2,yakuhai_chun:1 han=8 fu=60 pay=ron:24300 total=24300
~~~

~~~text
sc962 score hand=40m345999p567s22z melds=- win=3m by=ron seat=S round=S dora=6z ura=7z honba=2 flags=riichi
Python  sc962 yaku=aka:1,riichi:1 han=2 fu=40 pay=ron:3200 total=3200
Rust    sc962 yaku=aka:1,riichi:1 han=2 fu=50 pay=ron:3800 total=3800
~~~

~~~text
sc1008 score hand=067999m88p222s44z melds=- win=8p by=tsumo seat=N round=N dora=4m ura=8s flags=double_riichi
Python  sc1008 yaku=aka:1,dora:1,double_riichi:2,sanankou:2,tsumo:1 han=7 fu=40 pay=tsumo:3000/6000 total=12000
Rust    sc1008 yaku=aka:1,dora:1,double_riichi:2,sanankou:2,tsumo:1 han=7 fu=50 pay=tsumo:3000/6000 total=12000
~~~

~~~text
sc1077 score hand=122223067789s1z melds=- win=1z by=tsumo seat=E round=E dora=5m
Python  sc1077 yaku=aka:1,honitsu:3,tsumo:1 han=5 fu=30 pay=all:4000 total=12000
Rust    sc1077 yaku=aka:1,honitsu:3,tsumo:1 han=5 fu=40 pay=all:4000 total=12000
~~~

~~~text
sc1087 score hand=67889m22555777z melds=- win=7m by=ron seat=S round=S dora=6p ura=5p flags=double_riichi
Python  sc1087 yaku=double_riichi:2,honitsu:3,yakuhai_chun:1,yakuhai_haku:1 han=7 fu=50 pay=ron:12000 total=12000
Rust    sc1087 yaku=double_riichi:2,honitsu:3,yakuhai_chun:1,yakuhai_haku:1 han=7 fu=60 pay=ron:12000 total=12000
~~~

~~~text
sc1094 score hand=666m234444p56s22z melds=- win=7s by=ron seat=S round=S dora=8s ura=2z honba=3 flags=riichi
Python  sc1094 yaku=riichi:1 han=1 fu=40 pay=ron:2200 total=2200
Rust    sc1094 yaku=riichi:1 han=1 fu=50 pay=ron:2500 total=2500
~~~

~~~text
sc1120 score hand=44446p777s22444z melds=- win=5p by=ron seat=S round=S dora=5s
Python  sc1120 yaku=sanankou:2 han=2 fu=50 pay=ron:3200 total=3200
Rust    sc1120 yaku=sanankou:2 han=2 fu=60 pay=ron:3900 total=3900
~~~

~~~text
sc1124 score hand=34789m789s33555z melds=- win=5m by=ron seat=W round=W dora=3s
Python  sc1124 yaku=yakuhai_haku:1 han=1 fu=40 pay=ron:1300 total=1300
Rust    sc1124 yaku=yakuhai_haku:1 han=1 fu=50 pay=ron:1600 total=1600
~~~

~~~text
sc1172 score hand=777p22345s33666z melds=- win=2s by=tsumo seat=W round=W dora=3s ura=8m flags=riichi
Python  sc1172 yaku=dora:1,riichi:1,sanankou:2,tsumo:1,yakuhai_hatsu:1 han=6 fu=40 pay=tsumo:3000/6000 total=12000
Rust    sc1172 yaku=dora:1,riichi:1,sanankou:2,tsumo:1,yakuhai_hatsu:1 han=6 fu=50 pay=tsumo:3000/6000 total=12000
~~~

~~~text
sc1230 score hand=567789p34s44555z melds=- win=2s by=ron seat=N round=N dora=9s ura=2m honba=1 flags=riichi
Python  sc1230 yaku=riichi:1,yakuhai_haku:1 han=2 fu=40 pay=ron:2900 total=2900
Rust    sc1230 yaku=riichi:1,yakuhai_haku:1 han=2 fu=50 pay=ron:3500 total=3500
~~~

~~~text
sc1269 score hand=444456m23499p22z melds=- win=9p by=ron seat=S round=S dora=2m ura=2z honba=2 flags=double_riichi
Python  sc1269 yaku=double_riichi:2 han=2 fu=40 pay=ron:3200 total=3200
Rust    sc1269 yaku=double_riichi:2 han=2 fu=50 pay=ron:3800 total=3800
~~~

~~~text
sc3705 score hand=333788889p56s33z melds=- win=4s by=ron seat=W round=W dora=6m ura=9m flags=riichi
Python  sc3705 yaku=riichi:1 han=1 fu=40 pay=ron:1300 total=1300
Rust    sc3705 yaku=riichi:1 han=1 fu=50 pay=ron:1600 total=1600
~~~

~~~text
sc4052 score hand=22055m444p33666z melds=- win=2m by=ron seat=W round=W dora=1m4z
Python  sc4052 yaku=aka:1,dora:3,sanankou:2,toitoi:2,yakuhai_hatsu:1 han=9 fu=50 pay=ron:16000 total=16000
Rust    sc4052 yaku=aka:1,dora:3,sanankou:2,toitoi:2,yakuhai_hatsu:1 han=9 fu=60 pay=ron:16000 total=16000
~~~
