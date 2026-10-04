# xbrl.el

Query SEC EDGAR XBRL facts (10-K/10-Q financials) from Emacs via the data.sec.gov JSON APIs.

## Install

Emacs 29.1 or newer. Straight from GitHub:

    (package-vc-install "https://github.com/davidawad/xbrl.el")

Or from a checkout: add its directory to `load-path`, then `(require 'xbrl)`.

## Use

    (setq xbrl-user-agent "Your Name you@example.com") ; SEC requires this
    (xbrl-annual "AAPL" "Revenues")
    M-x xbrl-show-facts

See the [showcase](docs/README.md) for worked examples with screenshots, using
Snap Inc's annual reports.

Scope: SEC XBRL JSON APIs and read-only Inline XBRL fact extraction from an HTML
string via `xbrl-inline-facts`. Inline facts include their context and unit
metadata; this function does not fetch filings.

## Tests

Offline tests (the live test is skipped):

    emacs --batch -Q -L . -l test/xbrl-test.el -f ert-run-tests-batch-and-exit

To include the SEC live test:

    XBRL_LIVE=1 emacs --batch -Q -L . -l test/xbrl-test.el -f ert-run-tests-batch-and-exit
