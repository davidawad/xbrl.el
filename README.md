# xbrl.el

Query SEC EDGAR XBRL facts (10-K/10-Q financials) from Emacs via the data.sec.gov JSON APIs.

    (setq xbrl-user-agent "Your Name you@example.com") ; SEC requires this
    (xbrl-annual "AAPL" "Revenues")
    M-x xbrl-show-facts

Scope: numeric XBRL JSON APIs only. Inline-XBRL (narrative, footnotes) is not implemented.

Tests: `XBRL_LIVE=1 emacs -Q --batch -L . -l xbrl-test.el -f ert-run-tests-batch-and-exit`
