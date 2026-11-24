;;;; Issue #11: ENCODE and DECODE translate backend errors in place
;;;; (src/protocol.lisp, Errors and TRANSLATION).
;;;;
;;;; A handler that a check depends on is bound inside that check's OK, or,
;;;; for ESCAPING-ERROR, outside any OK. Rove's OK and DEFTEST bind an ERROR
;;;; handler that records a failure and unwinds, so a handler bound outside
;;;; them never runs. The restart functions run under GUARDED, so that one
;;;; that misses the backend's restart cannot reach a CONTINUE bound outside
;;;; the test run.

(in-package #:serdes-protocol/tests)

;;; A backend that runs its value (ENCODE) or its source (DECODE), a function,
;;; inside its own backend call.

(defclass thunk-backend (serdes-backend) ())

(defmethod backend-encode ((backend thunk-backend) value &key stream)
  (declare (ignore backend stream))
  (funcall value))

(defmethod backend-decode ((backend thunk-backend) source &key)
  (declare (ignore backend))
  (funcall source))

(register-format :serdes11 (make-instance 'thunk-backend))
(register-format :serdes11-outer (make-instance 'thunk-backend))

(defun call-thunk-backend (op thunk &optional (format :serdes11))
  "ENCODE (OP :ENCODE) or DECODE (OP :DECODE) with FORMAT. THUNK runs inside
the backend call."
  (ecase op
    (:encode (encode thunk :format format))
    (:decode (decode thunk :format format))))

(defun escaping-error (op thunk &optional (format :serdes11))
  "The first ERROR that a HANDLER-CASE around CALL-THUNK-BACKEND catches, or NIL
when the call returns."
  (handler-case (progn (call-thunk-backend op thunk format) nil)
    (error (c) c)))

;;; Backend conditions.

(define-condition item-unsupported (error)
  ((item :initarg :item :reader unsupported-item))
  (:report (lambda (c s) (format s "unsupported item ~S" (unsupported-item c))))
  (:documentation "A backend condition that is not a SERDES-ERROR."))

(define-condition item-unwritable (serdes-encode-error) ()
  (:documentation "A backend's recoverable encode condition, a SERDES-ERROR."))

(define-condition item-malformed (serdes-decode-error) ()
  (:documentation "A backend's recoverable decode condition, a SERDES-ERROR."))

(defvar *signalled* nil
  "The condition that the last RECOVERABLE-SITE signalled.")

(defun recoverable-site (type &rest initargs)
  "What a backend does where it can recover: signal a TYPE with ERROR, with the
restarts SKIP-ITEM (returns :SKIPPED) and USE-VALUE (returns its value)
associated with it (RESTART-CASE over an ERROR form)."
  (let ((c (apply #'make-condition type initargs)))
    (setf *signalled* c)
    (restart-case (error c)
      (skip-item () :report "Skip the item." :skipped)
      (use-value (value) :report "Use VALUE for the item." value))))

(defun unsupported-site ()
  (recoverable-site 'item-unsupported :item 3))

(defmacro guarded (&body body)
  "BODY, with CONTINUE and USE-VALUE restarts that return :GUARDED. A restart
function that misses the backend's restart then lands here, not on one bound
outside the test (ASDF and SBCL bind CONTINUE)."
  `(restart-case (progn ,@body)
     (continue () :guarded)
     (use-value (value) (declare (ignore value)) :guarded)))

;;; Translation of an ERROR that is not a SERDES-ERROR.

(deftest-parametrize translated-in-place
    ((op type verb) :ids ("encode" "decode")
     (:encode 'serdes-encode-error "encode")
     (:decode 'serdes-decode-error "decode"))
  (testing "it leaves the call as TYPE, with C as :CAUSE and the 0.2 message"
    (let ((e (escaping-error op #'unsupported-site)))
      (ok (typep e type))
      (ok (and (typep e 'serdes-error) (eq *signalled* (serdes-error-cause e))))
      (ok (and (typep e 'serdes-error)
               (equal (format nil "~A failed for ~S: ~A" verb :serdes11 *signalled*)
                      (serdes-error-message e))))))
  (testing "a handler outside sees E, and only E"
    (ok (let ((seen '()))
          (handler-case
              (handler-bind ((condition (lambda (c) (push c seen))))
                (call-thunk-backend op #'unsupported-site))
            (error (c)
              (and (= 1 (length seen))
                   (eq c (first seen))
                   (typep c type))))))
    (ok (let ((called nil))
          (handler-case
              (handler-bind ((item-unsupported (lambda (c) (setf called c))))
                (call-thunk-backend op #'unsupported-site))
            (serdes-error () (null called))))))
  (testing "a handler for E runs before anything unwinds and reaches the backend's restarts"
    (ok (eq :skipped
            (handler-bind ((serdes-error (lambda (e)
                                           (when (typep e type)
                                             (invoke-restart 'skip-item)))))
              (call-thunk-backend op #'unsupported-site))))
    (ok (eq :skipped
            (handler-bind ((serdes-error (lambda (e)
                                           (let ((r (and (typep e type) (find-restart 'skip-item e))))
                                             (when r (invoke-restart r))))))
              (call-thunk-backend op #'unsupported-site))))
    (ok (eql 42
             (guarded
               (handler-bind ((serdes-error (lambda (e)
                                              (when (typep e type)
                                                (use-value 42 e)))))
                 (call-thunk-backend op #'unsupported-site)))))
    (ok (eq :continued
            (guarded
              (handler-bind ((serdes-error (lambda (e)
                                             (when (typep e type)
                                               (continue e)))))
                (call-thunk-backend op (lambda ()
                                         (cerror "Go on." 'item-unsupported :item 4)
                                         :continued))))))
    (ok (equal '(:handler :cleanup)
               (let ((log '()))
                 (handler-case
                     (handler-bind ((serdes-error (lambda (e)
                                                    (when (typep e type)
                                                      (push :handler log)))))
                       (call-thunk-backend op (lambda ()
                                                (unwind-protect (unsupported-site)
                                                  (push :cleanup log)))))
                   (serdes-error () (reverse log)))))))
  (testing "E is not associated with restarts that apply to any condition"
    (ok (with-simple-restart (caller-restart "A restart of the caller.")
          (handler-case
              (handler-bind ((serdes-error
                               (lambda (e)
                                 (when (typep e type)
                                   (let ((other (make-condition 'simple-error
                                                                :format-control "other")))
                                     (unless (find-restart 'caller-restart other)
                                       (error "CALLER-RESTART is hidden from other conditions")))))))
                (call-thunk-backend op #'unsupported-site))
            (serdes-error () t)))))
  (testing "handlers the backend binds itself see C first"
    (ok (eq :skipped
            (handler-bind ((serdes-error (lambda (e)
                                           (declare (ignore e))
                                           (error "the handler outside was called"))))
              (call-thunk-backend op (lambda ()
                                       (handler-bind ((item-unsupported
                                                        (lambda (c)
                                                          (declare (ignore c))
                                                          (invoke-restart 'skip-item))))
                                         (unsupported-site)))))))))

;;; SERDES-ERRORs and other conditions pass untouched.

(deftest-parametrize serdes-errors-untouched
    ((op type) :ids ("encode" "decode")
     (:encode 'item-unwritable)
     (:decode 'item-malformed))
  (testing "a backend's SERDES-ERROR reaches a handler for its own type, restarts active"
    (ok (eq :skipped
            (handler-bind ((item-unwritable (lambda (c)
                                              (declare (ignore c))
                                              (invoke-restart 'skip-item)))
                           (item-malformed (lambda (c)
                                             (declare (ignore c))
                                             (invoke-restart 'skip-item))))
              (call-thunk-backend op (lambda () (recoverable-site type :message "bad item"))))))
    (ok (eql 7
             (guarded
               (handler-bind ((serdes-error (lambda (c) (use-value 7 c))))
                 (call-thunk-backend op (lambda () (recoverable-site type :message "bad item"))))))))
  (testing "it is the condition itself, without a cause"
    (let ((e (escaping-error op (lambda () (recoverable-site type :message "bad item")))))
      (ok (eq *signalled* e))
      (ok (typep e type))
      (ok (and (typep e 'serdes-error) (null (serdes-error-cause e))))))
  (testing "serdes's own errors are unchanged"
    (let ((e (escaping-error op (lambda () :never) :serdes11-missing)))
      (ok (typep e 'serdes-unknown-format))
      (ok (and (typep e 'serdes-unknown-format)
               (eq :serdes11-missing (serdes-unknown-format-format e))))
      (ok (and (typep e 'serdes-error) (null (serdes-error-cause e)))))))

(deftest-parametrize non-errors-untouched
    ((op) :ids ("encode" "decode")
     (:encode)
     (:decode))
  (ok (eq :done
          (handler-bind ((warning #'muffle-warning))
            (call-thunk-backend op (lambda () (warn "a backend warning") :done)))))
  (ok (eq :done
          (call-thunk-backend op (lambda ()
                                   (signal 'simple-condition :format-control "a note")
                                   :done)))))

;;; Nesting.

(deftest nested-calls-translate-innermost
  (let ((e (escaping-error :decode
                           (lambda () (call-thunk-backend :decode #'unsupported-site))
                           :serdes11-outer)))
    (ok (typep e 'serdes-decode-error))
    (ok (and (typep e 'serdes-error) (eq *signalled* (serdes-error-cause e))))
    (ok (and (typep e 'serdes-error)
             (equal (format nil "decode failed for ~S: ~A" :serdes11 *signalled*)
                    (serdes-error-message e)))))
  (ok (let ((seen '()))
        (handler-case
            (handler-bind ((serdes-error (lambda (c) (push c seen))))
              (call-thunk-backend :encode
                                  (lambda () (call-thunk-backend :decode #'unsupported-site))
                                  :serdes11-outer))
          (serdes-error (c)
            (and (= 1 (length seen))
                 (eq c (first seen))
                 (typep c 'serdes-decode-error))))))
  (ok (eq :skipped
          (handler-bind ((serdes-decode-error (lambda (e)
                                                (declare (ignore e))
                                                (invoke-restart 'skip-item))))
            (call-thunk-backend :decode
                                (lambda () (call-thunk-backend :decode #'unsupported-site))
                                :serdes11-outer)))))
