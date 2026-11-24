;;;; serdes-protocol conditions.
;;;;
;;;; SERDES-ERROR is the root. ENCODE and DECODE signal SERDES-ENCODE-ERROR and
;;;; SERDES-DECODE-ERROR for a backend ERROR that is not a SERDES-ERROR
;;;; (src/protocol.lisp, Errors). CAUSE (0.3.0) is that backend condition, the
;;;; same object (EQ); it is NIL for the errors serdes signals itself
;;;; (SERDES-UNKNOWN-FORMAT, the stream and event-parser defaults) and for the
;;;; SERDES-ERRORs a backend makes. MESSAGE is the report text.

(in-package #:serdes-protocol)

(define-condition serdes-error (error)
  ((message :initarg :message :reader serdes-error-message :initform nil)
   (cause :initarg :cause :reader serdes-error-cause :initform nil))
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
