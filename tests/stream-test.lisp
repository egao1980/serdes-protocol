(in-package #:serdes-protocol/tests)

(defun %ht (&rest pairs)
  (let ((h (make-hash-table :test #'equal)))
    (loop for (k v) on pairs by #'cddr
          do (setf (gethash k h) v))
    h))

(deftest sexp-stream-values
  (let ((raw (with-output-to-string (o)
               (let ((out (make-output-stream o :format :sexp)))
                 (stream-encode-value out (%ht "a" 1))
                 (stream-encode-value out #(2 3))))))
    (with-input-from-string (i raw)
      (let ((in (make-input-stream i :format :sexp)))
        (let ((v1 (stream-decode-value in))
              (v2 (stream-decode-value in)))
          (ok (hash-table-p v1))
          (ok (= 1 (gethash "a" v1)))
          (ok (equalp #(2 3) v2))
          (ok (eq :eof (stream-decode-value in))))))))

(deftest map-jsonl-sexp
  ;; map-jsonl is format-agnostic line decode; use :sexp lines
  (let ((raw (with-output-to-string (o)
               (let ((out (make-output-stream o :format :sexp)))
                 (stream-encode-value out 1)
                 (stream-encode-value out 2))))
        (acc '()))
    (map-jsonl (lambda (v) (push v acc)) raw :format :sexp)
    (ok (equal '(2 1) acc))))
