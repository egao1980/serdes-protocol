(in-package #:serdes-protocol)

(define-condition serdes-error (error)
  ((message :initarg :message :reader serdes-error-message :initform nil))
  (:report (lambda (c s)
             (format s "Serdes error~@[: ~a~]" (serdes-error-message c)))))

(define-condition serdes-encode-error (serdes-error) ())
(define-condition serdes-decode-error (serdes-error) ())

(define-condition serdes-unknown-format (serdes-error)
  ((format :initarg :format :reader serdes-unknown-format-format))
  (:report (lambda (c s)
             (format s "Unknown serdes format ~S~@[: ~a~]"
                     (serdes-unknown-format-format c)
                     (serdes-error-message c)))))
