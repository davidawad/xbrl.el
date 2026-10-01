;;; xbrl-test.el --- tests for xbrl.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'xbrl)

(ert-deftest xbrl-cik-pads ()
  (should (equal (xbrl-cik 320193) "CIK0000320193"))
  (should (equal (xbrl-cik "320193") "CIK0000320193")))

(ert-deftest xbrl-commas ()
  (should (equal (xbrl--commas 215639000000) "215,639,000,000"))
  (should (equal (xbrl--commas -1234) "-1,234")))

(ert-deftest xbrl-annual-dedupes-latest-filed ()
  (cl-letf (((symbol-function 'xbrl-concept)
             (lambda (&rest _)
               '((:val 1 :end "2020-09-26" :form "10-K" :fp "FY" :filed "2020-10-30")
                 (:val 2 :end "2020-09-26" :form "10-K" :fp "FY" :filed "2022-10-28")
                 (:val 3 :end "2021-09-25" :form "10-K" :fp "FY" :filed "2021-10-29")
                 (:val 9 :end "2021-12-25" :form "10-Q" :fp "Q1" :filed "2022-01-28")))))
    (let ((r (xbrl-annual "AAPL" "Revenues")))
      (should (equal (mapcar (lambda (f) (plist-get f :val)) r) '(2 3))))))

(ert-deftest xbrl-live-annual ()
  :tags '(network)
  (skip-unless (getenv "XBRL_LIVE"))
  (let ((r (xbrl-annual "AAPL" "RevenueFromContractWithCustomerExcludingAssessedTax")))
    (should (> (length r) 3))
    (should (numberp (plist-get (car r) :val)))))

(provide 'xbrl-test)
;;; xbrl-test.el ends here
