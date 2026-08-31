# Third-party notices

TeXLib-Installer — the installer scripts and templates in this repository — is
MIT licensed. See [LICENSE](LICENSE), which is kept as the unmodified MIT text
and nothing else: automated license detectors (GitHub's included, and the
policy scanners some institutions run before approving software) stop
recognising a license once anything is appended to it. What used to sit at the
bottom of that file is here instead.

## Components the installer downloads

The installer **bundles nothing**. Each component below is downloaded from its
vendor's official source at install time and hash-verified, under its own
license:

| Component | License | Source |
|---|---|---|
| Sublime Text 4 | commercial; install for evaluation | <https://www.sublimetext.com/eula> |
| SumatraPDF | GPLv3 | <https://www.sumatrapdfreader.org/> |
| TeX Live | mostly LPPL and similar | <https://tug.org/texlive/LICENSE.TL> |
| LaTeXTools | MIT | <https://github.com/SublimeText/LaTeXTools> |
| TeXLib library | MIT | <https://github.com/landonfox00/TeXLib> |

By running this installer you accept the licenses of every component it pulls
in. No proprietary binaries are redistributed here — the installer fetches them
directly from each vendor at install time.

Sublime Text is the one component with a commercial license. It is installed
for evaluation, which is what its EULA permits; continued use requires a
license from Sublime HQ. Nothing else in the set imposes a cost, and the
library itself does not require Sublime at all — since the `texlib_cli.py`
command line landed, `\documentclass{didactic}` builds from any editor or none.

`quiver.sty`, vendored inside the TeXLib library, has its own authorship and
terms; see that repository's
[THIRD-PARTY-NOTICES.md](https://github.com/landonfox00/TeXLib/blob/main/THIRD-PARTY-NOTICES.md).
