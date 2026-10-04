;;; xbrl-test.el --- tests for xbrl.el -*- lexical-binding: t; -*-

(require 'ert)

;; Coverage (undercover.el, pack-mandated).  Must run before the source loads.
(setq load-prefer-newer t)
(when (require 'undercover nil t)
  (undercover "xbrl.el" (:report-format 'text) (:send-report nil)))

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

;;; Real SEC data: Snap Inc (CIK 1564408), a Form 10-K filer under us-gaap.
;;; Payloads in test/fixtures/ are trimmed real SEC responses; see its README.

(defun xbrl-test--fixture (name)
  "Parse test/fixtures/NAME the same way `xbrl--get' parses SEC JSON."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name (concat "fixtures/" name)
                       xbrl-test--directory))
    (goto-char (point-min))
    (json-parse-buffer
     :object-type 'plist
     :array-type 'list
     :null-object nil
     :false-object nil)))

(defmacro xbrl-test--with-snap (&rest body)
  "Run BODY with `xbrl--get' serving the Snap fixtures."
  (declare (indent 0))
  `(xbrl-test--with-api
       `(("company_tickers" .
          ,(xbrl-test--fixture "company-tickers-snap.json"))
         ("companyfacts" .
          ,(xbrl-test--fixture "snap-companyfacts-names.json"))
         ("us-gaap/RevenueFromContractWithCustomerExcludingAssessedTax\\.json"
          .
          ,(xbrl-test--fixture "snap-us-gaap-revenue.json"))
         ("us-gaap/NetIncomeLoss\\.json"
          .
          ,(xbrl-test--fixture "snap-us-gaap-netincomeloss.json"))
         ("frames/us-gaap/RevenueFromContractWithCustomerExcludingAssessedTax/USD/CY2024"
          .
          ,(xbrl-test--fixture
            "frame-us-gaap-revenue-usd-cy2024.json")))
     ,@body))

(defconst xbrl-test--snap-revenue-concept
  "RevenueFromContractWithCustomerExcludingAssessedTax")

(defun xbrl-test--by-year (facts)
  "Alist of (YEAR . VAL) for annual FACTS."
  (mapcar
   (lambda (f)
     (cons
      (string-to-number
       (substring (plist-get f :end) 0 4))
      (plist-get f :val)))
   facts))

(ert-deftest xbrl-snap-annual-revenue ()
  (xbrl-test--with-snap
    (let ((r
           (xbrl-test--by-year
            (xbrl-annual "SNAP" xbrl-test--snap-revenue-concept))))
      (should (= (length r) 10))
      (should (= (cdr (assq 2016 r)) 404482000))
      (should (= (cdr (assq 2021 r)) 4117048000))
      (should (= (cdr (assq 2024 r)) 5361398000))
      (should (= (cdr (assq 2025 r)) 5931447000)))))

(ert-deftest xbrl-snap-annual-keeps-latest-filing ()
  (xbrl-test--with-snap
    (let ((f
           (car
            (last
             (xbrl-annual "SNAP" xbrl-test--snap-revenue-concept)))))
      (should (equal (plist-get f :unit) "USD"))
      (should (equal (plist-get f :form) "10-K"))
      (should (equal (plist-get f :end) "2025-12-31"))
      (should (equal (plist-get f :accn) "0001564408-26-000013")))))

(ert-deftest xbrl-snap-net-margin-by-year ()
  "Compose two concepts: net income / revenue per fiscal year."
  (xbrl-test--with-snap
    (let* ((rev
            (xbrl-test--by-year
             (xbrl-annual "SNAP" xbrl-test--snap-revenue-concept)))
           (ni
            (xbrl-test--by-year (xbrl-annual "SNAP" "NetIncomeLoss")))
           (margin
            (mapcar
             (lambda (y)
               (cons
                y
                (/ (round
                    (* 1000.0
                       (/ (float (cdr (assq y ni)))
                          (cdr (assq y rev)))))
                   10.0)))
             '(2021 2022 2023 2024 2025))))
      (should (= (cdr (assq 2025 ni)) -460489000))
      (should
       (equal
        margin
        '((2021 . -11.9)
          (2022 . -31.1)
          (2023 . -28.7)
          (2024 . -13.0)
          (2025 . -7.8)))))))

(ert-deftest xbrl-snap-concept-names ()
  (xbrl-test--with-snap
    (let ((names (xbrl-concept-names "SNAP")))
      (should (> (length names) 300))
      (should (member "NetIncomeLoss" names))
      (should (member xbrl-test--snap-revenue-concept names))
      (should (equal names (sort (copy-sequence names) #'string<))))))

(ert-deftest xbrl-frame-real-revenue-cy2024 ()
  (xbrl-test--with-snap
    (let* ((rows
            (xbrl-frame
             "us-gaap"
             xbrl-test--snap-revenue-concept
             "USD"
             "CY2024"))
           (rev
            (lambda (cik)
              (plist-get
               (seq-find (lambda (r) (= (plist-get r :cik) cik)) rows)
               :val))))
      (should (= (length rows) 5))
      (should (= (funcall rev 1564408) 5361398000))
      (should (= (funcall rev 1506293) 3646166000))
      (should (= (funcall rev 1713445) 1300205000)))))

(ert-deftest xbrl-show-facts-snap-table ()
  (xbrl-test--with-snap
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) "NetIncomeLoss"))
              ((symbol-function 'pop-to-buffer) #'ignore))
      (xbrl-show-facts "SNAP")
      (with-current-buffer "*xbrl*"
        (should (string-match-p "-460,489,000" (buffer-string)))
        (should
         (string-match-p "0001564408-26-000013" (buffer-string))))
      (kill-buffer "*xbrl*"))))

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
