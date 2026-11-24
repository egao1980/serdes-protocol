(defsystem "sexp-protocol"
  :version "0.3.0"
  :description "S-expression backend for serdes-protocol"
  :author "egao1980"
  :license "MIT"
  :depends-on ((:version "serdes-protocol" "0.3.0"))
  :serial t
  :pathname "src/sexp"
  :components ((:file "package")
               (:file "backend")))
