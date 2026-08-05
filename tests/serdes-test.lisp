(in-package #:serdes-protocol/tests)

(deftest unknown-format-condition
  (let ((condition (handler-case
                       (progn (encode "x" :format :missing) nil)
                     (serdes-unknown-format (e) e))))
    (ok (typep condition 'serdes-unknown-format))
    (ok (eq :missing (serdes-unknown-format-format condition)))))
