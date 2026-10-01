# AGENTS.md — xbrl.el

Standalone, publishable Emacs package for SEC XBRL financial facts, via the
data.sec.gov JSON APIs (companyfacts, companyconcept, frames). Everything is
plain Lisp returning plain data so filed 10-K/10-Q numbers compose into other
code. Scope boundary: this package knows XBRL semantics (concepts, facts,
contexts, units) and nothing about filings as documents -- that is the
sibling package `edgar.el`, which requires this one. Planned: inline-XBRL
(`ix:nonFraction`) tag extraction belongs HERE, not in edgar.el.

## For agents

- Read `README.md` first.
- Source is `src/xbrl.el`; tests are ERT in `test/xbrl-test.el`. Offline:
  `emacs -Q --batch -L src -l test/xbrl-test.el -f
  ert-run-tests-batch-and-exit`. The network test is skipped unless
  `XBRL_LIVE=1`; set `xbrl-user-agent` to a real name + email first (SEC
  requires it; keep under 10 req/s).
- `checkdoc-file`, `batch-byte-compile` (with `byte-compile-error-on-warn`)
  and package-lint must all be silent before any change lands.
- `xbrl-annual` keys facts on the period END year, not the API's `:fy`
  (which is the filing's fiscal year and repeats across restated comparatives)
  and keeps the latest-filed value per period.
- Zero references to the owner's dotfiles are allowed here -- the repo must
  remain publishable as-is. THIS repo is canonical; dotfiles imports it via
  load-path (`config/terminal/emacs/`) and carries no copy of the source.
- Authorized: david, swe.
