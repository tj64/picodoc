;; * Intro

;; ** Title & Copyright

;; picodoc.el - extract a documentation file from a (flat) PicoLisp source file
;; Version: 0.1
;; Copyright (c) 2013 Thorsten Jolitz
;; This file is NOT part of GNU emacs.

;; ** Credits 

;; This library builds on Org-mode, especially Org Babel with its support for
;; PicoLisp and PlantUML.


;; ** Contact:

;; For comments, bug reports, questions, etc, you can contact the author via
;; email: (format "tjolitz%sgmail%s" "@" ".com")

;; ** Comment

;; You can use the following (PicoLisp) code to convert a PicoLisp source file
;; (.l) into a 'flat' file (.flat) which is much easier to parse with regexp:

;; #+begin_src picolisp 
;;    (out "myfile.flat"
;;       (in "myfile.l"
;;          (while (read) (println @)) ) )
;; #+end_src

;; ** License:

;; This work is released under the GPL 2 or (at your option) any later
;; version.

;; * Requires

(require 'org)
(require 'ob-core)   ; changed from ob?
(require 'ob-picolisp)
(require 'ob-plantuml)

;; * Variables
;; ** Consts

(defconst picodoc-version "0.8"
  "PicoDoc version number.")

(defconst picodoc-header-string
  (concat
   "#+TITLE:      %s\n"
   "#+LANGUAGE:   en\n"
   "#+TEXT        Documentation for PicoLisp Source File '%s'\n"
   "#+OPTIONS:    H:3 num:nil toc:t\n"
   "#+DATE:       %s\n\n"
   )
  "String to be used with `format' for insertion as doc-file header")

(defconst picodoc-org-scrname "#+name: "
  "Org syntax for naming a source block.")

(defconst picodoc-org-beg-src-plantuml "#+begin_src plantuml :file %s.png"
  "Org syntax for beginning a plantuml source block, to be used with `format'.")

(defconst picodoc-org-beg-src-picolisp "#+begin_src picolisp "
  "Org syntax for beginning a picolisp source block.")

(defconst picodoc-org-end-src "#+end_src"
  "Org syntax for ending a source block.")


;; ** Vars
;; *** Variables

(defvar picodoc-joint-rel-temp-store nil
  "Temporary store for information about first side of joint relation.")

(setq picodoc-joint-rel-temp-store nil) ;FIXME makes sense here?

(defvar picodoc-unique-class-name-set nil
  "Set for storing all class names in a PicoLisp source file.

Helps avoiding accidental name collisions after replacing characters with
non-word syntax with the underscore '_'")

(setq picodoc-unique-class-name-set nil) ;FIXME makes sense here?



;; *** Hooks

(defvar picodoc-hook nil
  "Hook runs when PicoDoc is loaded.")

;; ** Customs
;; *** Groups

(defgroup picodoc nil
  "Library for extracting Org-mode doc-files from PicoLisp source-files."
  :prefix "picodoc-"
  :group 'lisp
  :link '(url-link "http://picolisp.com/5000/!wiki?home"))


;; *** Variables

(defcustom picodoc-function-regexp
"\\(^[ \\t]*(de \\)\\([^ ]+\\)\\( (?\\)\\([^()[:ascii:]]*\\)\\([ [:word:]]+\\)\\()?\\)"
  "Regexp used to identify PicoLisp function definitions."
  :group 'picodoc
  :type 'regexp)

(defcustom picodoc-class-regexp
  "\\(^[ \\t]*(class \\)\\([^)]+\\)\\()\\)"
  "Regexp used to identify PicoLisp class definitions."
  :group 'picodoc
  :type 'regexp)

(defcustom picodoc-extend-regexp
"\\(^[ \\t]*(extend \\)\\([^)]+\\)\\()\\)"
  "Regexp used to identify PicoLisp extend definitions."
  :group 'picodoc
  :type 'regexp)

(defcustom picodoc-method-regexp
  "\\(^[ \\t]*(dm \\)\\([^ ]+\\)\\( (\\)\\([^)]*\\)\\()\\)"
  "Regexp used to identify PicoLisp method definitions."
  :group 'picodoc
  :type 'regexp)

(defcustom picodoc-relation-regexp
"\\(^[ \\t]*(rel \\)\\([^ )]+\\)\\( (\\)\\([^)]+\\)\\() ?\\)\\([^()]*\\)\\((?\\)\\([^)]*\\)\\())?\\)"
  "Regexp used to identify PicoLisp relation definitions."
  :group 'picodoc
  :type 'regexp)

(defcustom picodoc-functions-headline "Functions"
  "String used as headline for subtree with function definitions."
  :group 'picodoc
  :type 'string)

(defcustom picodoc-public-functions-headline "Public Functions"
  "String used as headline for subtree with public function
definitions."
  :group 'picodoc
  :type 'string)

(defcustom picodoc-private-functions-headline "Private Functions"
  "String used as headline for subtree with private function
definitions."
  :group 'picodoc
  :type 'string)


(defcustom picodoc-classes-headline "Classes and Methods"
  "String used as headline for subtree with class definitions."
  :group 'picodoc
  :type 'string)

(defcustom picodoc-class-diagram-headline "Class Diagram"
  "String used as headline for subtree with class diagram."
  :group 'picodoc
  :type 'string)

(defcustom picodoc-class-diagram-suffix "-class-diagram"
  "String used as suffix for naming plantuml code-blocks and graphic-files."
  :group 'picodoc
  :type 'string)

(defcustom picodoc-entity-use-stereotype-p t
  "If non-nil, the inheritance relation to parent +Entity is shown as
stereotype in the subclass diagram instead as arrow."
  :group 'picodoc
  :type 'boolean)


;; * Functions
;; ** Source Code
;; *** Parse and Convert

(defun picodoc-write-doc (&optional in-file out-file)
  "Parse PicoLisp sources and write Org-mode documentation.

Parse the current buffer or PicoLisp source file IN-FILE and
  write its documentation to <buffer-name>.org (or Org-mode file
  OUT-FILE)."
  (interactive)
  (let* (
         ;; input file
         (in (or (and in-file
                      (string-equal (file-name-extension in-file) "flat")
                      (get-buffer-create in-file))
                 (and buffer-file-name
                      (string-equal
                       (file-name-extension
                        (buffer-file-name)) "flat")
                      (current-buffer))))
         (in-nondir-flat (and in
                         (file-name-nondirectory
                          (buffer-file-name in))))
         (in-nondir-source
          (concat (file-name-sans-extension in-nondir-flat) ".l"))
         ;; output-file
         (out (or (and out-file
                       (string-equal (file-name-extension out-file) "org")
                       (find-file-noselect out-file 'NOWARN))
                  (and in (find-file-noselect
                           (concat (file-name-sans-extension
                                    (buffer-file-name in)) ".org") 'NOWARN)))))
    (if (not in)
        (message (concat
                  "No valid (flat) PicoLisp source file "
                  "with extension '.flat' as input"))
      ;; (message "in: %s %s %s, out: %s %s %s"
      ;;          in (bufferp in) (buffer-file-name in)
      ;;          out (bufferp out) (buffer-file-name out)
      ;;          )

      ;; output file is not empty
      (and (> (buffer-size out) 0)
           (if (y-or-n-p "Output-file is not empty - overwrite? ")
               ;; delete contents of existing output file
               (save-excursion
                 (set-buffer out)
                 (widen)
                 (delete-region (point-min) (point-max)))
             ;; create new empty output file with unique name
             (setq out
                   (find-file-noselect
                    (concat (file-name-sans-extension
                             (buffer-file-name in))
                            "<"
                            (file-name-nondirectory
                             (make-temp-file ""))
                            ">"
                            ".org") 'NOWARN))))
      (save-excursion
        ;; prepare output buffer
        (with-current-buffer out
          (org-check-for-org-mode)
          (beginning-of-buffer)
          ;; header
          (insert
           (format picodoc-header-string
                   in-nondir-source
                   in-nondir-source
                   (format-time-string
                    "<%Y-%m-%d %a %H:%M>")))
          (end-of-buffer)
          ;; top-level entry
          (insert "* Definitions")
          (newline)
          ;; second-level entry 'functions'
          (insert (concat "** " picodoc-functions-headline))
          (beginning-of-line)
          (org-insert-property-drawer)
          (org-entry-put (point) "exports" "code")
          (org-entry-put (point) "results" "silent")
          (end-of-buffer)
          (newline)
          ;; third-level entry 'public functions'
          (insert (concat "*** " picodoc-public-functions-headline))
          (newline)
          ;; third-level entry 'private functions'
          (insert (concat "*** " picodoc-private-functions-headline))
          (newline)
          ;; second-level entry 'classes and methods'
          (insert (concat "** " picodoc-classes-headline))
          (newline)
          ;; third-level entry 'class diagram'
          (insert (concat "*** " picodoc-class-diagram-headline))
          (beginning-of-line)
          (org-insert-property-drawer)
          (org-entry-put (point) "exports" "results")
          (org-entry-put (point) "results" "replace")
          (end-of-buffer)
          (newline)
          ;; plantuml code block
          (insert
           (concat
            picodoc-org-scrname
            (file-name-sans-extension in-nondir-flat)
            picodoc-class-diagram-suffix))
          (newline)
          (insert
           (format
            picodoc-org-beg-src-plantuml
            (concat
             (file-name-sans-extension in-nondir-flat)
             picodoc-class-diagram-suffix)))
          (newline)
          (insert (format "title <b>%s</b>%sClass Diagram" in-nondir-flat "\\n"))
          (newline 2)
          (insert picodoc-org-end-src)

          ;; parse and convert input file
          (with-current-buffer in
            (save-excursion
              (save-restriction
                (widen)
                (goto-char (point-min))
                (while (not (eobp))
                  (cond
                   ;; function definition
                   ((looking-at picodoc-function-regexp)
                    (let ((signature (match-string-no-properties 0))
                          (function-name (match-string-no-properties 2)))
                      (with-current-buffer out
                        (goto-char
                         (org-find-exact-headline-in-buffer
                          picodoc-functions-headline
                          (current-buffer)
                          'POS-ONLY))
                        (org-insert-heading-after-current)
                        (org-demote)
                        (insert function-name)
                        (newline 2)
                        (insert picodoc-org-beg-src-picolisp)
                        (newline)
                        (insert (concat signature " ... )"))
                        (newline)
                        (insert picodoc-org-end-src)
                        (newline))))
                   ;; class definition
                   ((looking-at picodoc-class-regexp)
                    (let* ((classes (match-string-no-properties 2))
                           (class-list
                            (split-string-and-unquote
                             classes " "))
                           (new-class
                            (car class-list))
                           (new-class-name
                            (replace-regexp-in-string
                             "[^[:word:]]" "_"
                             (cadr (split-string new-class "+"))))
                           (new-class-name-enhanced
                            (if (numberp
                                 (compare-strings
                                  (downcase new-class-name) 0 1
                                  new-class-name 0 1))
                                (concat "class " new-class-name)
                              (concat "abstract class " new-class-name)))
                           (parent-classes-complete
                            (and (> (length class-list) 1)
                                 (cdr class-list)))
                           (new-class-name-enhanced-entity-stereotype
                            (and
                             parent-classes-complete
                             (member "+Entity" parent-classes-complete)
                             picodoc-entity-use-stereotype-p
                             (concat
                              new-class-name-enhanced
                              " <<Entity>>")))
                           (class-name
                            (or
                             new-class-name-enhanced-entity-stereotype
                             new-class-name-enhanced))
                           (parent-classes-no-entity
                            (and
                             new-class-name-enhanced-entity-stereotype
                             (remove "+Entity" parent-classes-complete)))
                           (parent-classes
                            (if new-class-name-enhanced-entity-stereotype
                                parent-classes-no-entity
                              parent-classes-complete)))
                      (with-current-buffer out
                        (org-babel-goto-named-src-block
                         (concat
                          (file-name-sans-extension in-nondir-flat)
                          picodoc-class-diagram-suffix))
                        (re-search-forward
                         org-babel-src-block-regexp)
                        (forward-line -1)
                        ;; inheritance
                        (if parent-classes
                            (mapc
                             (lambda (parent)
                               (let ((parent-name
                                      (replace-regexp-in-string
                                       "[^[:word:]]" "_"
                                       (cadr
                                        (split-string
                                         parent "+")))))
                                 (insert
                                  (format "%s <|-- %s\n"
                                          ;; parent class
                                          (if (numberp
                                               (compare-strings
                                                (downcase parent-name) 0 1
                                                parent-name 0 1))
                                              ;; concrete
                                              (concat "class " parent-name)
                                            ;; abstract
                                            (concat
                                             "abstract class " parent-name))
                                          ;; new class
                                          class-name))))
                             parent-classes)
                          ;; no inheritance
                          (insert
                           (format "%s\n"
                                   ;; new class
                                   class-name))))))
                   ;; class extension
                   ((looking-at picodoc-extend-regexp)
                    (let* ((class
                            (match-string-no-properties 2))
                           (class-name
                            (replace-regexp-in-string
                             "[^[:word:]]" "_"
                             (cadr (split-string class "+"))))
                           (class-name-enhanced
                            (if (numberp
                                 (compare-strings
                                  (downcase class-name) 0 1
                                  class-name 0 1))
                                (concat "class " class-name)
                              (concat "abstract class " class-name))))
                      (with-current-buffer out
                        (org-babel-goto-named-src-block
                         (concat
                          (file-name-sans-extension in-nondir-flat)
                          picodoc-class-diagram-suffix))
                        (re-search-forward
                         org-babel-src-block-regexp)
                        (forward-line -1)
                        (insert
                         (format "%s <<extends>>\n"
                                 class-name-enhanced)))))
                   ;; relation definition
                   ((looking-at picodoc-relation-regexp)
                    (let* ((match (match-string-no-properties 0))
                           (attr-name (match-string-no-properties 2))
                           (rel-classes (match-string-no-properties 4))
                           (args (match-string-no-properties 6))
                           (args-classes (match-string-no-properties 8))
                           (rel-class-list
                            (split-string-and-unquote
                             (mapconcat 'identity
                                        (split-string
                                         rel-classes " ") "") "+"))
                           (rel-class-string
                            (concat
                             "rel["
                             (mapconcat
                              'identity rel-class-list " ")
                             "] "))
                           (args-class-list
                            (split-string-and-unquote
                             (mapconcat 'identity
                                        (split-string
                                         args-classes " ") "") "+"))
                           (class
                            (save-excursion
                              (re-search-backward
                               (concat
                                "\\("
                                picodoc-class-regexp
                                "\\|"
                                picodoc-extend-regexp
                                "\\)"))
                              (or
                               (and
                                (match-string-no-properties 3)
                                (car
                                 (split-string
                                  (match-string-no-properties 3) " ")))
                               (match-string-no-properties 6))))
                           (class-name
                            (replace-regexp-in-string
                             "[^[:word:]]" "_"
                             (cadr (split-string
                                    class "+")))))
                      ;; (message
                      ;;  "%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n"
                      ;;  class
                      ;;  class-name
                      ;;  match
                      ;;  attr-name
                      ;;  rel-classes
                      ;;  rel-class-list
                      ;;  args
                      ;;  args-classes
                      ;;  args-class-list)
                      (with-current-buffer out
                        (org-babel-goto-named-src-block
                         (concat
                          (file-name-sans-extension in-nondir-flat)
                          picodoc-class-diagram-suffix))
                        (re-search-forward
                         org-babel-src-block-regexp)
                        (forward-line -1)
                        (insert
                         (cond
                          ((member "Link" rel-class-list)
                           (concat
                            (format "%s %s o-- %s\n"
                                    class-name
                                    (concat
                                     (if (member "List" rel-class-list)
                                         "\"              * "
                                       "\"             ")
                                     attr-name
                                     "\"")
                                    (replace-regexp-in-string
                                     "[^[:word:]]" "_"
                                     (car args-class-list)))
                            (format "%s : %s\n"
                                    class-name
                                    (concat
                                     "+"
                                     rel-class-string
                                     attr-name))))
                          ((member "Joint" rel-class-list)
                           (concat
                            (format "%s %s o-- %s\n"
                                    class-name
                                    (concat
                                     (if (member "List" args-class-list)
                                         "\"              * "
                                       "\"             1 ")
                                     attr-name
                                     "\"")
                                    (concat
                                     (if (member "List" rel-class-list)
                                         "\"              * "
                                       "\"             1 ")
                                     args
                                     "\" "
                                     (replace-regexp-in-string
                                      "[^[:word:]]" "_"
                                      (car args-class-list))))
                            (format "%s : %s\n"
                                    class-name
                                    (concat
                                     "+"
                                     rel-class-string
                                     attr-name))))
                          (t
                           (format "%s : %s\n"
                                   class-name
                                   (concat
                                    "+"
                                    rel-class-string
                                    attr-name))))))))

                   ;; method definition
                   ((looking-at picodoc-method-regexp)
                    (let* (;;(signature (match-string-no-properties 0))
                           (method (match-string-no-properties 2))
                           (method-args (match-string-no-properties 4))
                           (method-name
                            (car (split-string
                                  method ">")))
                           (method-name-with-visibility ; TODO transient symbols
                            (concat "+" method-name))
                           (class
                            (save-excursion
                              (re-search-backward
                               (concat
                                "\\("
                                picodoc-class-regexp
                                "\\|"
                                picodoc-extend-regexp
                                "\\)"))
                              (or
                               (and
                                (match-string-no-properties 3)
                                (car
                                 (split-string
                                  (match-string-no-properties 3) " ")))
                               (match-string-no-properties 6))))
                           (class-name
                            (replace-regexp-in-string
                             "[^[:word:]]" "_"
                             (cadr (split-string
                                    class "+")))))
                      (with-current-buffer out
                        (org-babel-goto-named-src-block
                         (concat
                          (file-name-sans-extension in-nondir-flat)
                          picodoc-class-diagram-suffix))
                        (re-search-forward
                         org-babel-src-block-regexp)
                        (forward-line -1)
                        (insert
                         (format "%s : %s\n"
                                 class-name
                                 (concat
                                  method-name-with-visibility
                                  "(" method-args ")")))))))
                  (forward-char))))))))))

;; ** Tests
;; *** Parse and Convert

;; * Outro

(provide 'picodoc)

;; Local Variables:
;; coding: utf-8
;; mode: emacs-lisp
;; eval: (outline-minor-mode)
;; eval: (rainbow-mode)
;; ispell-local-dictionary: "en_US"
;; End:

;;; picodoc.el ends here
