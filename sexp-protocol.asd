(defsystem "sexp-protocol"
  :version "0.1.0"
  :description "S-expression backend for serdes-protocol"
  :author "egao1980"
  :license "MIT"
  :depends-on ("serdes-protocol")
  :serial t
  :pathname "src/sexp"
  :components ((:file "package")
               (:file "backend")))
