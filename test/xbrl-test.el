;;; xbrl-test.el --- tests for xbrl.el -*- lexical-binding: t; -*-

(require 'ert)

;; Coverage (undercover.el, pack-mandated).  Must run before the source loads.
(setq load-prefer-newer t)
(when (require 'undercover nil t)
  (undercover "src/*.el" (:report-format 'text) (:send-report nil)))

(require 'xbrl)

(defconst xbrl-test--directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing this test file.")

(ert-deftest xbrl-cik-pads ()
  (should (equal (xbrl-cik 320193) "CIK0000320193"))
  (should (equal (xbrl-cik "320193") "CIK0000320193")))

(ert-deftest xbrl-commas ()
  (should (equal (xbrl--commas 215639000000) "215,639,000,000"))
  (should (equal (xbrl--commas -1234) "-1,234")))

(ert-deftest xbrl-annual-dedupes-latest-filed ()
  (cl-letf (((symbol-function 'xbrl-concept)
             (lambda (&rest _)
               '((:val
                  1
                  :end "2020-09-26"
                  :form "10-K"
                  :fp "FY"
                  :filed "2020-10-30")
                 (:val
                  2
                  :end "2020-09-26"
                  :form "10-K"
                  :fp "FY"
                  :filed "2022-10-28")
                 (:val
                  3
                  :end "2021-09-25"
                  :form "10-K"
                  :fp "FY"
                  :filed "2021-10-29")
                 (:val
                  9
                  :end "2021-12-25"
                  :form "10-Q"
                  :fp "Q1"
                  :filed "2022-01-28")))))
    (let ((r (xbrl-annual "AAPL" "Revenues")))
      (should
       (equal (mapcar (lambda (f) (plist-get f :val)) r) '(2 3))))))

;;; Hermetic tests: `xbrl--get' is stubbed with canned SEC payloads.

(defmacro xbrl-test--with-api (routes &rest body)
  "Run BODY with `xbrl--get' answering from ROUTES, an alist of (REGEXP . DATA)."
  (declare (indent 1))
  `(let ((xbrl--tickers nil))
     (cl-letf (((symbol-function 'xbrl--get)
                (lambda (url)
                  (or (cdr
                       (cl-find-if
                        (lambda (r)
                          (string-match-p (car r) url))
                        ,routes))
                      (error "Unexpected URL %s" url)))))
       ,@body)))

(defconst xbrl-test--tickers
  '(:0
    (:cik_str 320193 :ticker "AAPL" :title "Apple Inc.")
    :1 (:cik_str 789019 :ticker "MSFT" :title "MICROSOFT CORP")))

(ert-deftest xbrl-cik-resolves-ticker ()
  (xbrl-test--with-api `(("company_tickers" . ,xbrl-test--tickers))
    (should (equal (xbrl-cik "aapl") "CIK0000320193"))
    (should (equal (xbrl-cik "MSFT") "CIK0000789019"))
    (should-error (xbrl-cik "NOPE"))))

(ert-deftest xbrl-concept-tags-unit ()
  (xbrl-test--with-api
      `(("company_tickers" . ,xbrl-test--tickers)
        ("companyconcept/CIK0000320193/us-gaap/Revenues"
         .
         (:units (:USD ((:val 5 :end "2020-09-26" :form "10-K"))))))
    (let ((r (xbrl-concept "AAPL" "us-gaap" "Revenues")))
      (should (equal (plist-get (car r) :unit) "USD"))
      (should (= (plist-get (car r) :val) 5)))))

(ert-deftest xbrl-frame-returns-data ()
  (xbrl-test--with-api '(("frames/us-gaap/Revenues/USD/CY2023"
                          .
                          (:data ((:cik 1 :val 7)))))
    (should
     (equal
      (xbrl-frame "us-gaap" "Revenues" "USD" "CY2023")
      '((:cik 1 :val 7))))))

(ert-deftest xbrl-concept-names-sorted ()
  (xbrl-test--with-api `(("company_tickers" . ,xbrl-test--tickers)
                         ("companyfacts" .
                          (:facts
                           (:us-gaap (:Revenues nil :Assets nil)))))
    (should
     (equal (xbrl-concept-names "AAPL") '("Assets" "Revenues")))))

(ert-deftest xbrl-inline-facts-match-companyfacts-for-apple-2025-10k
    ()
  (let*
      ((fixture
        (with-temp-buffer
          (insert-file-contents
           (expand-file-name "fixtures/aapl-2025-10k-inline.html"
                             xbrl-test--directory))
          (buffer-string)))
       (inline
        (seq-find
         (lambda (fact)
           (and
            (equal
             (plist-get fact :name)
             "us-gaap:RevenueFromContractWithCustomerExcludingAssessedTax")
            (equal
             (plist-get
              (plist-get fact :context)
              :end)
             "2025-09-27")))
         (xbrl-inline-facts fixture)))
       (company-facts
        (xbrl-test--with-api
            `(("company_tickers" . ,xbrl-test--tickers)
              ("companyconcept/CIK0000320193/us-gaap/RevenueFromContractWithCustomerExcludingAssessedTax"
               .
               (:units
                (:USD
                 ((:val
                   416161000000
                   :start "2024-09-29"
                   :end "2025-09-27"
                   :form "10-K"
                   :filed "2025-10-31"
                   :accn "0000320193-25-000079"))))))
          (seq-find
           (lambda (fact)
             (equal (plist-get fact :accn) "0000320193-25-000079"))
           (xbrl-concept
            "AAPL"
            "us-gaap"
            "RevenueFromContractWithCustomerExcludingAssessedTax")))))
    (should inline)
    (should company-facts)
    (should
     (= (plist-get inline :value) (plist-get company-facts :val)))
    (should (equal (plist-get inline :unit) "USD"))
    (should
     (equal
      (plist-get (plist-get inline :context) :entity) "0000320193"))
    (should
     (equal
      (plist-get (plist-get inline :context) :start)
      (plist-get company-facts :start)))
    (should
     (equal
      (plist-get (plist-get inline :context) :end)
      (plist-get company-facts :end)))))

(ert-deftest
    xbrl-inline-facts-retain-dimensions-footnotes-and-continuations
    ()
  (let*
      ((html
        (concat
         "<html><body>"
         "<xbrli:context id='c'><xbrli:entity><xbrli:identifier>1</xbrli:identifier></xbrli:entity>"
         "<xbrli:period><xbrli:instant>2025-12-31</xbrli:instant></xbrli:period>"
         "<xbrli:scenario><xbrli:typedMember dimension='ex:RegionAxis'><ex:Region>West</ex:Region></xbrli:typedMember></xbrli:scenario></xbrli:context>"
         "<ix:nonNumeric name='ex:Description' contextRef='c' continuedAt='c1' footnoteRefs='fn1'>A &amp; </ix:nonNumeric>"
         "<ix:continuation id='c1'>B</ix:continuation>"
         "<ix:footnote id='fn1'>Source note</ix:footnote>"
         "</body></html>"))
       (fact (car (xbrl-inline-facts html))))
    (should (equal (plist-get fact :value) "A & B"))
    (should (equal (plist-get fact :footnotes) '("Source note")))
    (should
     (equal
      (plist-get (plist-get fact :context) :dimensions)
      '(("ex:RegionAxis" . "West"))))
    (should
     (equal
      (plist-get (plist-get fact :context) :instant) "2025-12-31"))))

(ert-deftest xbrl-show-concept-renders-table ()
  (cl-letf (((symbol-function 'xbrl-annual)
             (lambda (&rest _)
               '((:val
                  1234567
                  :end "2024-09-28"
                  :unit "USD"
                  :filed "2024-11-01"
                  :accn "0000320193-24-000123")))))
    (xbrl-show-concept "AAPL" "Revenues")
    (with-current-buffer "*xbrl*"
      (should (string-match-p "1,234,567" (buffer-string)))
      (should (string-match-p "2024-09-28" (buffer-string))))
    (kill-buffer "*xbrl*")))

(ert-deftest xbrl-sort-val-numeric ()
  (should
   (xbrl--sort-val
    '(nil ["" "9" "" "" ""]) '(nil ["" "10" "" "" ""])))
  (should-not
   (xbrl--sort-val
    '(nil ["" "1,000" "" "" ""]) '(nil ["" "999" "" "" ""]))))

(ert-deftest xbrl-get-rejects-non-200 ()
  (cl-letf (((symbol-function 'url-retrieve-synchronously)
             (lambda (&rest _)
               (let ((b (generate-new-buffer " *xbrl-fake*")))
                 (with-current-buffer b
                   (insert "HTTP/1.1 403 Forbidden\r\n\r\n"))
                 b))))
    (should-error (xbrl--get "https://example.invalid/x"))))

(ert-deftest xbrl-get-parses-json ()
  (cl-letf
      (((symbol-function 'url-retrieve-synchronously)
        (lambda (&rest _)
          (let ((b (generate-new-buffer " *xbrl-fake*")))
            (with-current-buffer b
              (insert
               "HTTP/1.1 200 OK\r\nX: y\r\n\r\n{\"a\":[1,2],\"b\":null}"))
            b))))
    (should
     (equal
      (xbrl--get "https://example.invalid/x") '(:a (1 2) :b nil)))))

(ert-deftest xbrl-live-annual ()
  :tags
  '(network)
  (skip-unless (getenv "XBRL_LIVE"))
  (let ((r
         (xbrl-annual
          "AAPL"
          "RevenueFromContractWithCustomerExcludingAssessedTax")))
    (should (> (length r) 3))
    (should (numberp (plist-get (car r) :val)))))

(provide 'xbrl-test)
;;; xbrl-test.el ends here
