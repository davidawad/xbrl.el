;; -*- mode: eask; lexical-binding: t -*-
;; Package manifest + dev tooling for xbrl.el.  The development block is the
;; swe-project-plugin-pack-elisp tool cohort (formatter, linters, coverage,
;; property/e2e testing, complexity metrics).  Git-source deps are not on
;; MELPA and are pinned to a commit SHA (the pack's tools.json says so).

(package "xbrl"
         "0.1.0"
         "SEC XBRL financial facts")

(website-url "https://github.com/davidawad/xbrl.el")
(keywords "finance" "data" "tools")

(package-file "src/xbrl.el")
(files "src/*.el")

(script "test" "eask test ert test/xbrl-test.el")
(script "check"
        "eask lint package && eask lint checkdoc && eask lint regexps && UNDERCOVER_FORCE=true eask test ert test/xbrl-test.el && eask compile src/xbrl.el")

(source 'gnu)
(source 'melpa)

(depends-on "emacs" "29.1")

(development
 (depends-on "package-lint")
 (depends-on "relint")
 (depends-on "elisp-autofmt")
 (depends-on "undercover")
 (depends-on "ecukes")
 (depends-on "dash")
 (depends-on "propcheck"
             :url "https://github.com/Wilfred/propcheck"
             :fetcher 'git
             :commit "21075792c03a186bc89029871c6db119e6e13cf0")
 (depends-on "codemetrics"
             :url "https://github.com/emacs-vs/codemetrics"
             :fetcher 'git
             :commit "863a9ac167ecdf20f3730fd9d308d44314fce903")
 (depends-on "cognitive-complexity"
             :url "https://github.com/emacs-vs/cognitive-complexity"
             :fetcher 'git
             :commit "b45afe9bf65943f985b645cea514212dc734349b"))
