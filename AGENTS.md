# AGENTS.md — xbrl.el

Standalone, publishable Emacs package for SEC XBRL financial facts, via the
data.sec.gov JSON APIs (companyfacts, companyconcept, frames). Everything is
plain Lisp returning plain data so filed 10-K/10-Q numbers compose into other
code. Scope boundary: this package knows XBRL semantics (concepts, facts,
contexts, units) and nothing about filings as documents -- that is the
sibling package `edgar.el`, which requires this one. Inline-XBRL
(`ix:nonFraction`) tag extraction (`xbrl-inline-facts`) lives HERE, not in
edgar.el.

## For agents

- Read `README.md` first.
- Tooling is the `swe-project-plugin-pack-elisp` cohort, declared in `Eask`
  (install once: `eask install-deps --dev`; needs `eask-cli` from brew).
  One command runs every gate: `eask run script check` (package-lint,
  checkdoc, relint, ERT with undercover coverage, byte-compile). Format with
  `eask format elisp-autofmt src/xbrl.el test/xbrl-test.el` BEFORE
  committing. Also installed, run by hand: propcheck (property tests),
  ecukes (e2e), codemetrics + cognitive-complexity (warn-only metrics).
- Source is `src/xbrl.el`; tests are ERT in `test/xbrl-test.el`. Almost all
  tests are hermetic (`xbrl--get` stubbed with canned SEC payloads); the one
  network test needs `XBRL_LIVE=1`. Set `xbrl-user-agent` to a real name +
  email first (SEC requires it; stay under 10 req/s). Coverage is ~80%.
- Git-source cohort deps in `Eask` are pinned to commit SHAs.
- `xbrl-annual` keys facts on the period END year, not the API's `:fy`
  (which is the filing's fiscal year and repeats across restated comparatives)
  and keeps the latest-filed value per period.
- Zero references to the owner's dotfiles are allowed here -- the repo must
  remain publishable as-is. THIS repo is canonical; dotfiles imports it via
  load-path (`config/terminal/emacs/`) and carries no copy of the source.
- Authorized: david, swe.
