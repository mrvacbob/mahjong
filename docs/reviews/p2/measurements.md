# Shootout measurements

Measured by the coordinator, the same way for every entry, on one machine
(Apple silicon, macOS). Not taken from the entries' own notes.

- **Corpus**: 12,434 cases. **Held-back**: 11,569 cases (agari, shanten, waits,
  score) generated from a different seed after the entries were finished; no
  held-back `legal` cases, because the legal generator is replay-based and has no seed.
- **Lines**: non-blank lines that are not whole-line comments, source files only
  (no build scripts or package manifests). Python docstrings are counted.
- **req/s**: whole-process throughput per op on the corpus, including start-up.
  One run each, so treat differences under about 30% as noise.

| Language | Model | Lines | Corpus fails | Held-back fails | agari | shanten | waits | score | legal |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Swift | opus | 1020 | 0 | 0 | 173,677 | 175,524 | 37,846 | 77,984 | 19,252 |
| Swift | codex | 770 | 0 | 0 | 174,394 | 123,635 | 50,426 | 114,308 | 67,006 |
| Swift | agy | 1983 | 0 | 0 | 204,572 | 205,913 | 40,113 | 155,151 | 31,256 |
| Mercury | opus | 1338 | 0 | 0 | 143,386 | 32,800 | 3,738 | 92,655 | 4,795 |
| Mercury | codex | 832 | 0 | 0 | 174,103 | 27,998 | 5,975 | 115,211 | 15,233 |
| Mercury | agy | 1996 | 0 | 0 | 162,893 | 43,946 | 14,914 | 95,009 | 11,218 |
| Python | opus | 962 | 0 | 0 | 33,820 | 28,784 | 4,112 | 20,946 | 3,076 |
| Python | codex | 631 | 0 | 0 | 31,749 | 23,733 | 4,454 | 23,295 | 5,430 |
| Python | agy | 1364 | 0 | 0 | 49,840 | 33,426 | 5,697 | 29,721 | 4,262 |
| Haskell | opus | 794 | 0 | 0 | 62,648 | 26,472 | 3,933 | 52,739 | 10,649 |
| Haskell | codex | 626 | 0 | 0 | 60,386 | 4,043 | 2,282 | 66,153 | 22,192 |
| Haskell | agy | 1363 | 0 | 0 | 118,583 | 47,112 | 3,666 | 89,516 | 10,162 |
