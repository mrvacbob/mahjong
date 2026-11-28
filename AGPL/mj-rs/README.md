# mj-rs — libriichi-based reference checker (AGPL-3.0)

A test-generation and cross-checking tool. It answers the protocol in
`Spec/formats.md` using code derived from
[Mortal](https://github.com/Equim-chan/Mortal)'s `libriichi`, and generates
`Corpus/legal.txt`.

License: GNU AGPL-3.0 (see `LICENSE.libriichi`), because `src/` contains
modified copies of libriichi modules (`prepare_vendor.py` shows which and how).
This directory is separate from the rest of the repository: the engine does not
link to it, include it, or copy from it, and must not. It communicates with the
engine only through the text protocol and corpus files.

Build and usage: see `NOTES.md`.
