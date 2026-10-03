# xbrl.el

Query SEC EDGAR XBRL facts (10-K/10-Q financials) from Emacs via the data.sec.gov JSON APIs.

    (setq xbrl-user-agent "Your Name you@example.com") ; SEC requires this
    (xbrl-annual "AAPL" "Revenues")
    M-x xbrl-show-facts

Scope: SEC XBRL JSON APIs and read-only Inline XBRL fact extraction from an HTML
string via `xbrl-inline-facts`. Inline facts include their context and unit
metadata; this function does not fetch filings.

Tests: `XBRL_LIVE=1 emacs -Q --batch -L src -l test/xbrl-test.el -f ert-run-tests-batch-and-exit`
