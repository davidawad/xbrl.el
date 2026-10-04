;;; xbrl.el --- SEC XBRL financial facts -*- lexical-binding: t; -*-

;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: finance, data, tools
;; URL: https://github.com/davidawad/xbrl.el

;;; Commentary:

;; Query SEC EDGAR's XBRL JSON APIs (data.sec.gov) from Emacs.
;;
;; Every function is plain Lisp returning plain data, so filed 10-K/10-Q
;; facts can be composed in your own code:
;;
;;   (xbrl-concept "AAPL" "us-gaap" "Revenues")      ; list of fact plists
;;   (xbrl-annual "AAPL" "Revenues")                  ; 10-K facts, deduped by FY
;;   (xbrl-frame "us-gaap" "Revenues" "USD" "CY2023") ; one concept, all filers
;;
;; Interactive: `xbrl-show-concept', `xbrl-show-facts'.
;;
;; SEC requires a descriptive User-Agent; set `xbrl-user-agent'.
;; Scope: the XBRL JSON APIs plus read-only extraction of Inline XBRL facts
;; from filing HTML.  This package does not fetch filing documents.

;;; Code:

(require 'url)
(require 'json)
(require 'seq)
(require 'subr-x)
(require 'cl-lib)
(require 'dom)

(defgroup xbrl nil
  "SEC XBRL access."
  :group 'tools)

(defcustom xbrl-user-agent
  (format "%s %s"
          (user-full-name)
          (or user-mail-address "unknown@example.com"))
  "User-Agent sent to SEC.  SEC asks for a name and contact email."
  :type 'string)

(defconst xbrl--api "https://data.sec.gov/api/xbrl")

;;;; Transport

(defun xbrl--get (url)
  "Fetch URL and return parsed JSON as hash-table-free plist/list data."
  (let ((url-request-extra-headers
         `(("User-Agent" . ,xbrl-user-agent)))
        (buf (url-retrieve-synchronously url t t 30)))
    (unless buf
      (error "XBRL: no response from %s" url))
    (with-current-buffer buf
      (unwind-protect
          (progn
            (goto-char (point-min))
            (unless (looking-at "HTTP/[0-9.]+ 200")
              (error
               "XBRL: %s -> %s"
               url
               (buffer-substring (point) (line-end-position))))
            (re-search-forward "\r?\n\r?\n")
            (json-parse-buffer
             :object-type 'plist
             :array-type 'list
             :null-object nil
             :false-object nil))
        (kill-buffer buf)))))

;;;; Ticker -> CIK

(defvar xbrl--tickers nil
  "Cached alist of (TICKER CIK TITLE).")

(defun xbrl--load-tickers ()
  "Return the cached ticker table, fetching it from SEC on first use."
  (or xbrl--tickers
      (setq xbrl--tickers
            (let
                ((raw
                  (xbrl--get
                   "https://www.sec.gov/files/company_tickers.json")))
              (cl-loop
               for (_ v) on raw by #'cddr collect
               (list
                (upcase (plist-get v :ticker))
                (plist-get v :cik_str)
                (plist-get v :title)))))))

(defun xbrl-cik (ticker-or-cik)
  "Return a 10-digit zero-padded CIK string for TICKER-OR-CIK."
  (let ((n
         (if (or (integerp ticker-or-cik)
                 (string-match-p "\\`[0-9]+\\'" ticker-or-cik))
             (string-to-number (format "%s" ticker-or-cik))
           (or (cadr
                (assoc (upcase ticker-or-cik) (xbrl--load-tickers)))
               (error "XBRL: unknown ticker %s" ticker-or-cik)))))
    (format "CIK%010d" n)))

;;;; Core queries

(defun xbrl-facts (ticker)
  "All XBRL facts for TICKER (raw companyfacts plist).  Large."
  (xbrl--get
   (format "%s/companyfacts/%s.json" xbrl--api (xbrl-cik ticker))))

(defun xbrl-concept-raw (ticker taxonomy concept)
  "Raw companyconcept payload for TICKER, TAXONOMY and CONCEPT."
  (xbrl--get
   (format "%s/companyconcept/%s/%s/%s.json"
           xbrl--api
           (xbrl-cik ticker)
           taxonomy
           concept)))

(defun xbrl-concept (ticker taxonomy concept &optional unit)
  "Facts for CONCEPT of TICKER as a list of plists.
Each has :val :start :end :fy :fp :form :filed :accn :unit.  UNIT defaults
to the first unit present (usually USD).  TAXONOMY is e.g. \"us-gaap\"."
  (let* ((units
          (plist-get
           (xbrl-concept-raw ticker taxonomy concept)
           :units))
         (key
          (if unit
              (intern (concat ":" unit))
            (car units)))
         (rows (plist-get units key)))
    (mapcar
     (lambda (r)
       (plist-put
        (copy-sequence r)
        :unit (substring (symbol-name key) 1)))
     rows)))

(defconst xbrl--annual-forms '("10-K" "20-F" "40-F")
  "Annual report form types: domestic (10-K) and foreign private issuer.")

(defun xbrl-annual (ticker concept &optional taxonomy unit)
  "Latest-filed annual-report value per fiscal year for CONCEPT of TICKER.
Counts Form 10-K, 20-F and 40-F facts.  Returns facts sorted by period
end ascending.  TAXONOMY defaults to us-gaap; foreign private issuers
typically report under \"ifrs-full\".  UNIT is as for `xbrl-concept'
\(default: the first unit present)."
  (let ((by-fy (make-hash-table :test 'eql)))
    (dolist (f
             (xbrl-concept ticker (or taxonomy "us-gaap") concept
                           unit))
      (when (and (member (plist-get f :form) xbrl--annual-forms)
                 (equal (plist-get f :fp) "FY"))
        ;; Key on period end year, not :fy (which is the filing's FY).
        (let* ((end (plist-get f :end))
               (yr (string-to-number (substring end 0 4)))
               (old (gethash yr by-fy)))
          (when (or (null old)
                    (string>
                     (plist-get f :filed) (plist-get old :filed)))
            (puthash yr f by-fy)))))
    (sort (hash-table-values by-fy)
          (lambda (a b)
            (string< (plist-get a :end) (plist-get b :end))))))

;;;; Inline XBRL

(defun xbrl--inline-text (node)
  "Return text under NODE, omitting Inline XBRL exclude elements."
  (cond
   ((stringp node)
    node)
   ((and (consp node) (not (eq (car node) 'exclude)))
    (mapconcat #'xbrl--inline-text (cddr node) ""))
   (t
    "")))

(defun xbrl--inline-first-text (node tag)
  "Return the text of NODE's first descendant named TAG, or nil."
  (when-let* ((element (car (dom-by-tag node tag))))
    (string-trim (xbrl--inline-text element))))

(defun xbrl--inline-context (element)
  "Return normalized context fields from Inline XBRL context ELEMENT."
  (let ((period (car (dom-by-tag element 'period))))
    (list
     :entity (xbrl--inline-first-text element 'identifier)
     :start (and period (xbrl--inline-first-text period 'startdate))
     :end (and period (xbrl--inline-first-text period 'enddate))
     :instant (and period (xbrl--inline-first-text period 'instant))
     :dimensions
     (mapcar
      (lambda (member)
        (cons
         (dom-attr member 'dimension)
         (string-trim (xbrl--inline-text member))))
      (append
       (dom-by-tag element 'explicitmember)
       (dom-by-tag element 'typedmember))))))

(defun xbrl--inline-unit (element)
  "Return the normalized measure text from Inline XBRL unit ELEMENT."
  (when-let* ((measure (xbrl--inline-first-text element 'measure)))
    (replace-regexp-in-string "\\`iso4217:" "" measure)))

(defun xbrl--inline-continued-text (element continuations)
  "Return ELEMENT text followed by its continuation chain.
CONTINUATIONS maps Inline XBRL continuation ids to DOM elements."
  (let ((text (xbrl--inline-text element))
        (next (dom-attr element 'continuedat))
        (seen (make-hash-table :test #'equal)))
    (while (and next
                (not (gethash next seen))
                (gethash next continuations))
      (puthash next t seen)
      (let ((continuation (gethash next continuations)))
        (setq
         text (concat text (xbrl--inline-text continuation))
         next (dom-attr continuation 'continuedat))))
    text))

(defun xbrl--inline-fact-elements (node)
  "Return Inline XBRL fact elements under NODE in document order."
  (when (consp node)
    (append
     (when (memq (car node) '(nonfraction nonnumeric))
       (list node))
     (mapcan #'xbrl--inline-fact-elements (cddr node)))))

(defun xbrl--inline-number (text format scale sign)
  "Convert Inline XBRL numeric TEXT using FORMAT, SCALE, and SIGN."
  (let* ((text (string-trim text))
         (dash-p
          (or (string-empty-p text) (member text '("-" "—" "–"))))
         (negative-p
          (or (equal sign "-") (string-match-p "\\`(.*)\\'" text)))
         (number-text
          (cond
           (dash-p
            "0")
           ((and format (string-match-p "num-comma-decimal" format))
            (replace-regexp-in-string
             "\\." "" (replace-regexp-in-string "," "." text t t)
             t t))
           (t
            (replace-regexp-in-string "[, \t\r\n\u00a0]" "" text))))
         (number-text
          (if (string-match-p "\\`(.*)\\'" number-text)
              (substring number-text 1 -1)
            number-text)))
    (when (string-match-p
           "\\`[+-]?[0-9]+\\(?:\\.[0-9]+\\)?\\'" number-text)
      (let* ((number (string-to-number number-text))
             (scaled
              (* number
                 (expt
                  10
                  (if scale
                      (string-to-number scale)
                    0)))))
        (if negative-p
            (- (abs scaled))
          scaled)))))

(defun xbrl-inline-facts (html)
  "Parse Inline XBRL facts from HTML and return them as plists.
Each fact includes :name, :taxonomy, :concept, :value, :context-id,
:context, :unit, :footnotes, :decimals, :scale, :sign, and :id.  Numeric
:value is scaled to its reported magnitude; non-numeric values remain strings."
  (unless (stringp html)
    (signal 'wrong-type-argument (list 'stringp html)))
  (with-temp-buffer
    (insert html)
    (let* ((tree (libxml-parse-html-region (point-min) (point-max)))
           (contexts (make-hash-table :test #'equal))
           (units (make-hash-table :test #'equal))
           (continuations (make-hash-table :test #'equal))
           (footnotes (make-hash-table :test #'equal))
           facts)
      (dolist (element (dom-by-tag tree 'context))
        (when-let* ((id (dom-attr element 'id)))
          (puthash id (xbrl--inline-context element) contexts)))
      (dolist (element (dom-by-tag tree 'unit))
        (when-let* ((id (dom-attr element 'id)))
          (puthash id (xbrl--inline-unit element) units)))
      (dolist (element (dom-by-tag tree 'continuation))
        (when-let* ((id (dom-attr element 'id)))
          (puthash id element continuations)))
      (dolist (element (dom-by-tag tree 'footnote))
        (when-let* ((id (dom-attr element 'id)))
          (puthash
           id (string-trim (xbrl--inline-text element)) footnotes)))
      (dolist (element (xbrl--inline-fact-elements tree))
        (let* ((tag (car element))
               (name (dom-attr element 'name))
               (separator (and name (string-match ":" name)))
               (format (dom-attr element 'format))
               (scale (dom-attr element 'scale))
               (sign (dom-attr element 'sign))
               (context-id (dom-attr element 'contextref))
               (unit-ref (dom-attr element 'unitref))
               (raw-value
                (string-trim
                 (xbrl--inline-continued-text element continuations)))
               (value
                (if (eq tag 'nonfraction)
                    (xbrl--inline-number raw-value format scale sign)
                  raw-value))
               (fact-footnotes
                (delq
                 nil
                 (mapcar
                  (lambda (id) (gethash id footnotes))
                  (split-string
                   (or (dom-attr element 'footnoterefs) "")
                   "[ \t\r\n]+" t)))))
          (when (and name context-id value)
            (push
             (list
              :name name
              :taxonomy (and separator (substring name 0 separator))
              :concept
              (if separator
                  (substring name (1+ separator))
                name)
              :value value
              :context-id context-id
              :context (gethash context-id contexts)
              :unit (and unit-ref (gethash unit-ref units))
              :unit-ref unit-ref
              :footnotes fact-footnotes
              :decimals (dom-attr element 'decimals)
              :scale scale
              :sign sign
              :format format
              :id (dom-attr element 'id))
             facts))))
      (nreverse facts))))

(defun xbrl-frame (taxonomy concept unit period)
  "CONCEPT in TAXONOMY across all filers, in UNIT, for PERIOD.
PERIOD looks like \"CY2023\" or \"CY2023Q4I\"."
  (plist-get
   (xbrl--get
    (format "%s/frames/%s/%s/%s/%s.json"
            xbrl--api
            taxonomy
            concept
            unit
            period))
   :data))

(defun xbrl-concept-names (ticker &optional taxonomy)
  "Sorted concept names TICKER has reported under TAXONOMY (default us-gaap)."
  (let* ((tax (intern (concat ":" (or taxonomy "us-gaap"))))
         (facts
          (plist-get (plist-get (xbrl-facts ticker) :facts) tax)))
    (sort (cl-loop
           for
           (k _)
           on
           facts
           by
           #'cddr
           collect
           (substring (symbol-name k) 1))
          #'string<)))

;;;; Interactive

(defun xbrl--read-ticker ()
  "Prompt for a ticker with completion over SEC's ticker table."
  (completing-read "Ticker: " (mapcar #'car (xbrl--load-tickers))
                   nil
                   nil))

(defun xbrl--fmt (n)
  "Format N with thousands separators; pass non-numbers through."
  (if (numberp n)
      (format "%s" (xbrl--commas n))
    (format "%s" n)))

(defun xbrl--commas (n)
  "Return number N as a string with thousands separators."
  (let ((s (number-to-string n)))
    (while (string-match "\\`\\(-?[0-9]+\\)\\([0-9]\\{3\\}\\)" s)
      (setq s (replace-match "\\1,\\2" t nil s)))
    s))

;;;###autoload
(defun xbrl-show-concept (ticker concept &optional taxonomy)
  "Show annual values of CONCEPT for TICKER in a table.
TAXONOMY defaults to us-gaap."
  (interactive (let ((tk (xbrl--read-ticker)))
                 (list
                  tk
                  (completing-read "Concept: " (xbrl-concept-names tk)
                                   nil nil))))
  (let ((rows (xbrl-annual ticker concept taxonomy)))
    (with-current-buffer (get-buffer-create "*xbrl*")
      (xbrl-mode)
      (setq
       tabulated-list-format
       [("Period end" 12 t)
        ("Value" 24 xbrl--sort-val :right-align t)
        ("Unit" 6 t)
        ("Filed" 12 t)
        ("Accession" 22 t)]
       tabulated-list-entries
       (mapcar
        (lambda (f)
          (list
           (plist-get f :accn)
           (vector
            (plist-get f :end)
            (xbrl--fmt (plist-get f :val))
            (plist-get f :unit)
            (plist-get f :filed)
            (plist-get f :accn))))
        rows)
       header-line-format (format " %s  %s" (upcase ticker) concept))
      (tabulated-list-init-header)
      (tabulated-list-print)
      (pop-to-buffer (current-buffer)))))

(defun xbrl--sort-val (a b)
  "Return non-nil if table entry A's value column precedes B's."
  (< (string-to-number
      (replace-regexp-in-string "," "" (aref (cadr a) 1)))
     (string-to-number
      (replace-regexp-in-string "," "" (aref (cadr b) 1)))))

;;;###autoload
(defun xbrl-show-facts (ticker &optional taxonomy)
  "Browse every TAXONOMY concept TICKER reports, then show its annual values.
TAXONOMY defaults to us-gaap."
  (interactive (list (xbrl--read-ticker)))
  (let ((names (xbrl-concept-names ticker taxonomy)))
    (xbrl-show-concept
     ticker (completing-read "Concept: " names nil t)
     taxonomy)))

(define-derived-mode
 xbrl-mode
 tabulated-list-mode
 "XBRL"
 "Major mode for SEC XBRL fact tables.")

(provide 'xbrl)
;;; xbrl.el ends here
