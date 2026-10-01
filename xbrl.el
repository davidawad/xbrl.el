;;; xbrl.el --- SEC XBRL financial facts for Emacs -*- lexical-binding: t; -*-

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
;; Scope: the XBRL JSON APIs only.  Inline-XBRL narrative/footnote parsing
;; is not implemented.

;;; Code:

(require 'url)
(require 'json)
(require 'seq)
(require 'subr-x)

(defgroup xbrl nil "SEC XBRL access." :group 'tools)

(defcustom xbrl-user-agent
  (format "%s %s" (user-full-name) (or user-mail-address "unknown@example.com"))
  "User-Agent sent to SEC.  SEC asks for a name and contact email."
  :type 'string)

(defconst xbrl--api "https://data.sec.gov/api/xbrl")

;;;; Transport

(defun xbrl--get (url)
  "Fetch URL and return parsed JSON as hash-table-free plist/list data."
  (let ((url-request-extra-headers `(("User-Agent" . ,xbrl-user-agent)))
        (buf (url-retrieve-synchronously url t t 30)))
    (unless buf (error "xbrl: no response from %s" url))
    (with-current-buffer buf
      (unwind-protect
          (progn
            (goto-char (point-min))
            (unless (looking-at "HTTP/[0-9.]+ 200")
              (error "xbrl: %s -> %s" url
                     (buffer-substring (point) (line-end-position))))
            (re-search-forward "\r?\n\r?\n")
            (json-parse-buffer :object-type 'plist :array-type 'list
                               :null-object nil :false-object nil))
        (kill-buffer buf)))))

;;;; Ticker -> CIK

(defvar xbrl--tickers nil "Cached alist of (TICKER CIK TITLE).")

(defun xbrl--load-tickers ()
  (or xbrl--tickers
      (setq xbrl--tickers
            (let ((raw (xbrl--get "https://www.sec.gov/files/company_tickers.json")))
              (cl-loop for (_ v) on raw by #'cddr
                       collect (list (upcase (plist-get v :ticker))
                                     (plist-get v :cik_str)
                                     (plist-get v :title)))))))

(defun xbrl-cik (ticker-or-cik)
  "Return a 10-digit zero-padded CIK string for TICKER-OR-CIK."
  (let ((n (if (or (integerp ticker-or-cik)
                   (string-match-p "\\`[0-9]+\\'" ticker-or-cik))
               (string-to-number (format "%s" ticker-or-cik))
             (or (cadr (assoc (upcase ticker-or-cik) (xbrl--load-tickers)))
                 (error "xbrl: unknown ticker %s" ticker-or-cik)))))
    (format "CIK%010d" n)))

;;;; Core queries

(defun xbrl-facts (ticker)
  "All XBRL facts for TICKER (raw companyfacts plist).  Large."
  (xbrl--get (format "%s/companyfacts/%s.json" xbrl--api (xbrl-cik ticker))))

(defun xbrl-concept-raw (ticker taxonomy concept)
  (xbrl--get (format "%s/companyconcept/%s/%s/%s.json"
                     xbrl--api (xbrl-cik ticker) taxonomy concept)))

(defun xbrl-concept (ticker taxonomy concept &optional unit)
  "Facts for CONCEPT of TICKER as a list of plists.
Each has :val :start :end :fy :fp :form :filed :accn :unit.  UNIT defaults
to the first unit present (usually USD)."
  (let* ((units (plist-get (xbrl-concept-raw ticker taxonomy concept) :units))
         (key (if unit (intern (concat ":" unit)) (car units)))
         (rows (plist-get units key)))
    (mapcar (lambda (r) (plist-put (copy-sequence r) :unit (substring (symbol-name key) 1)))
            rows)))

(defun xbrl-annual (ticker concept &optional taxonomy)
  "Latest-filed 10-K value per fiscal year for CONCEPT of TICKER.
Returns facts sorted by :fy ascending.  TAXONOMY defaults to us-gaap."
  (let ((by-fy (make-hash-table :test 'eql)))
    (dolist (f (xbrl-concept ticker (or taxonomy "us-gaap") concept))
      (when (and (equal (plist-get f :form) "10-K") (equal (plist-get f :fp) "FY"))
        ;; Key on period end year, not :fy (which is the filing's FY).
        (let* ((end (plist-get f :end))
               (yr (string-to-number (substring end 0 4)))
               (old (gethash yr by-fy)))
          (when (or (null old)
                    (string> (plist-get f :filed) (plist-get old :filed)))
            (puthash yr f by-fy)))))
    (sort (hash-table-values by-fy)
          (lambda (a b) (string< (plist-get a :end) (plist-get b :end))))))

(defun xbrl-frame (taxonomy concept unit period)
  "CONCEPT across all filers for PERIOD (e.g. \"CY2023\", \"CY2023Q4I\")."
  (plist-get (xbrl--get (format "%s/frames/%s/%s/%s/%s.json"
                                xbrl--api taxonomy concept unit period))
             :data))

(defun xbrl-concept-names (ticker &optional taxonomy)
  "Sorted concept names TICKER has reported under TAXONOMY (default us-gaap)."
  (let* ((tax (intern (concat ":" (or taxonomy "us-gaap"))))
         (facts (plist-get (plist-get (xbrl-facts ticker) :facts) tax)))
    (sort (cl-loop for (k _) on facts by #'cddr collect (substring (symbol-name k) 1))
          #'string<)))

;;;; Interactive

(defun xbrl--read-ticker ()
  (completing-read "Ticker: " (mapcar #'car (xbrl--load-tickers)) nil nil))

(defun xbrl--fmt (n)
  (if (numberp n) (format "%s" (xbrl--commas n)) (format "%s" n)))

(defun xbrl--commas (n)
  (let ((s (number-to-string n)))
    (while (string-match "\\`\\(-?[0-9]+\\)\\([0-9]\\{3\\}\\)" s)
      (setq s (replace-match "\\1,\\2" t nil s)))
    s))

;;;###autoload
(defun xbrl-show-concept (ticker concept)
  "Show annual 10-K values of us-gaap CONCEPT for TICKER."
  (interactive
   (let ((tk (xbrl--read-ticker)))
     (list tk (completing-read "Concept: " (xbrl-concept-names tk) nil nil))))
  (let ((rows (xbrl-annual ticker concept)))
    (with-current-buffer (get-buffer-create "*xbrl*")
      (xbrl-mode)
      (setq tabulated-list-format
            [("Period end" 12 t) ("Value" 24 xbrl--sort-val :right-align t)
             ("Unit" 6 t) ("Filed" 12 t) ("Accession" 22 t)]
            tabulated-list-entries
            (mapcar (lambda (f)
                      (list (plist-get f :accn)
                            (vector (plist-get f :end)
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
  (< (string-to-number (replace-regexp-in-string "," "" (aref (cadr a) 1)))
     (string-to-number (replace-regexp-in-string "," "" (aref (cadr b) 1)))))

;;;###autoload
(defun xbrl-show-facts (ticker)
  "Browse every us-gaap concept TICKER reports; RET shows annual values."
  (interactive (list (xbrl--read-ticker)))
  (let ((names (xbrl-concept-names ticker)))
    (xbrl-show-concept ticker (completing-read "Concept: " names nil t))))

(define-derived-mode xbrl-mode tabulated-list-mode "XBRL"
  "Major mode for SEC XBRL fact tables.")

(provide 'xbrl)
;;; xbrl.el ends here
