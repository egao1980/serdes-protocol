(defsystem "serdes-protocol"
  :version "0.3.0"
  :description "CLOS serialization protocol for cl-stack — whole-value + Gray/JSONL/events"
  :author "egao1980"
  :license "MIT"
  :depends-on ("babel" "trivial-gray-streams")
  :properties (:cl-repo (:ci (:with ("sexp-protocol"))))
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "conditions")
               (:file "protocol")
               (:file "streams"))
  :in-order-to ((test-op (test-op "serdes-protocol/tests"))))

(defsystem "serdes-protocol/tests"
  :depends-on ("serdes-protocol" "sexp-protocol" (:version "rove" "0.11.1"))
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "serdes-test")
               (:file "sexp-test")
               (:file "stream-test")
               (:file "serdes11-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
