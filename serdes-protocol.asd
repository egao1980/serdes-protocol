(defsystem "serdes-protocol"
  :version "0.2.1"
  :description "CLOS serialization protocol for cl-stack — whole-value + Gray/JSONL/events"
  :author "egao1980"
  :license "MIT"
  :depends-on ("babel" "trivial-gray-streams")
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "conditions")
               (:file "protocol")
               (:file "streams"))
  :in-order-to ((test-op (test-op "serdes-protocol/tests"))))

(defsystem "serdes-protocol/tests"
  :depends-on ("serdes-protocol" "sexp-protocol" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "serdes-test")
               (:file "sexp-test")
               (:file "stream-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
