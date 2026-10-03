# xbrl.el

Query SEC EDGAR XBRL facts (10-K/10-Q financials) from Emacs via the data.sec.gov JSON APIs.

## Install from a checkout

Add the package's `src` directory to `load-path`, then load it:

    (add-to-list 'load-path "/path/to/xbrl.el/src")
    (require 'xbrl)

    (setq xbrl-user-agent "Your Name you@example.com") ; SEC requires this
    (xbrl-annual "AAPL" "Revenues")
    M-x xbrl-show-facts

Scope: SEC XBRL JSON APIs and read-only Inline XBRL fact extraction from an HTML
string via `xbrl-inline-facts`. Inline facts include their context and unit
metadata; this function does not fetch filings.

## Tests

Offline tests (the live test is skipped):

    emacs --batch -Q -L src -l test/xbrl-test.el -f ert-run-tests-batch-and-exit

To include the SEC live test:

    XBRL_LIVE=1 emacs --batch -Q -L src -l test/xbrl-test.el -f ert-run-tests-batch-and-exit
