;;;; serdes-protocol: the format registry and whole-value ENCODE / DECODE.
;;;;
;;;; Errors (0.3.0, CLHS 9; issue #11). ENCODE and DECODE make the backend
;;;; call: find the backend for FORMAT (%BACKEND-FOR, which signals
;;;; SERDES-UNKNOWN-FORMAT) and call BACKEND-ENCODE / BACKEND-DECODE on it. The
;;;; call runs inside a HANDLER-BIND for ERROR; there is no HANDLER-CASE, so
;;;; serdes unwinds nothing. For a condition C signalled during the call:
;;;;   - C is not an ERROR (a warning, a SIGNAL of a plain condition): serdes
;;;;     does nothing.
;;;;   - C is a SERDES-ERROR (serdes's own, or one a backend signals): serdes
;;;;     does nothing. C reaches the caller's handlers where it was signalled,
;;;;     with the backend's restarts active. 0.2 unwound first, then signalled
;;;;     C again from ENCODE (DECODE).
;;;;   - any other ERROR: TRANSLATION, below.
;;;; Handlers that the backend binds are more recent than the one ENCODE
;;;; (DECODE) binds, so they see C first, and only they see it.
;;;;
;;;; TRANSLATION. The handler calls %TRANSLATE-BACKEND-ERROR, which does not
;;;; return. It runs in C's dynamic environment, before anything unwinds, and
;;;; signals with ERROR a fresh E of type SERDES-ENCODE-ERROR
;;;; (SERDES-DECODE-ERROR) that has
;;;;   :CAUSE    C itself (EQ),
;;;;   :MESSAGE  (format nil "encode failed for ~S: ~A" FORMAT C), or "decode
;;;;             failed for ~S: ~A" for DECODE, where FORMAT is the argument as
;;;;             given (the 0.2 text).
;;;; During that signal, every restart associated with C (CLHS 9.1.4.2.2, such
;;;; as those a RESTART-CASE ties to C's ERROR form) is also associated with E
;;;; (WITH-CONDITION-RESTARTS). Restarts that are not associated with any
;;;; condition stay unassociated. For the handlers bound outside ENCODE
;;;; (DECODE), this means:
;;;;   - They see E and never C, most recent first. A HANDLER-CASE or
;;;;     HANDLER-BIND for ERROR or CONDITION gets E, as in 0.2.
;;;;   - The backend's restarts are active while they run. (invoke-restart
;;;;     'name), (find-restart 'name e) and the restart functions given E, such
;;;;     as (use-value v e) and (continue e), all reach them. So a handler for
;;;;     SERDES-DECODE-ERROR can invoke a backend's skip restart.
;;;;   - The backend's UNWIND-PROTECT cleanups run when a handler transfers
;;;;     control, after that handler is called. 0.2 ran them before.
;;;;   - If no handler transfers control, the debugger is entered with E and
;;;;     the backend's restarts.
;;;; A handler for the backend's own condition type that is bound around
;;;; ENCODE (DECODE) is not called for a translated C. To act on that type,
;;;; bind SERDES-ERROR and test (SERDES-ERROR-CAUSE E), or call BACKEND-DECODE
;;;; (BACKEND-ENCODE) on FIND-BACKEND, which translates nothing. When a
;;;; backend's recoverable conditions subclass SERDES-DECODE-ERROR
;;;; (SERDES-ENCODE-ERROR), they pass through untouched, so handlers can bind
;;;; their types directly.
;;;; Nesting: an ENCODE or DECODE inside a backend call translates C itself.
;;;; The outer call passes that E along untouched, because E is a SERDES-ERROR.
;;;; Why C is not signalled to the outside first, with E only if C is
;;;; declined: any outer handler that acts on every ERROR (Rove's OK and
;;;; DEFTEST, a request loop's catch-all) would then take C, and a caller's
;;;; handler for SERDES-DECODE-ERROR inside it would never run. Why C is not
;;;; signalled after E is declined: a handler for C's type would then run only
;;;; when no handler outside acts on E, which never happens under a test runner
;;;; or a server.
;;;;
;;;; ENCODE-TO-OCTETS and DECODE-OCTETS go through ENCODE and DECODE. The
;;;; stream, JSONL and event-parser functions (src/streams.lisp) call the
;;;; backend directly and translate nothing.

(in-package #:serdes-protocol)

(defvar *serdes-format* :json
  "Default serialization format keyword.")

(defvar *serdes-backend* nil
  "Optional current backend object for *SERDES-FORMAT*.")

(defvar *serdes-formats* (make-hash-table :test #'eq)
  "Map normalized format keywords to backend objects.")

(defvar *serdes-media-types* (make-hash-table :test #'eq)
  "Map format keywords to primary MIME type strings (type/subtype).")

(defvar *serdes-media-type-index* (make-hash-table :test #'equal)
  "Map lowercase type/subtype strings to format keywords.")

(defvar *serdes-binary-formats* (make-hash-table :test #'eq)
  "Map format keywords to T when the wire form is octets.")

(defparameter *default-media-types*
  '((:json "application/json" "text/json")
    (:yaml "application/yaml" "text/yaml" "application/x-yaml")
    (:sexp "application/x-lisp")
    (:csv "text/csv")
    (:tsv "text/tab-separated-values")
    (:xml "application/xml" "text/xml")
    (:arrow "application/vnd.apache.arrow.file")
    (:parquet "application/vnd.apache.parquet")
    (:protobuf "application/x-protobuf" "application/protobuf")
    (:wkt "application/x-protobuf")
    (:cbor "application/cbor")
    (:msgpack "application/msgpack" "application/x-msgpack")
    (:messagepack "application/msgpack" "application/x-msgpack")
    (:avro "application/avro" "avro/binary")
    (:mime "message/rfc822")
    (:multipart "multipart/form-data" "multipart/mixed"))
  "Well-known Content-Type values for format keywords. First entry is primary.")

(defparameter *default-binary-formats*
  '(:arrow :parquet :protobuf :wkt :cbor :messagepack :msgpack :avro)
  "Formats whose ENCODE returns octets.")

(defclass serdes-backend () ()
  (:documentation "Base class for serdes-protocol backends."))

(defgeneric backend-encode (backend value &key stream)
  (:documentation "Encode VALUE, returning a string unless STREAM is supplied."))

(defgeneric backend-decode (backend source &key)
  (:documentation "Decode SOURCE, usually a string, octet vector, or character stream."))

(defgeneric backend-media-type (backend)
  (:documentation "Primary MIME type/subtype for BACKEND, or NIL.")
  (:method ((backend serdes-backend))
    (declare (ignore backend))
    nil))

(defgeneric backend-binary-p (backend)
  (:documentation "True when BACKEND's wire form is an octet vector.")
  (:method ((backend serdes-backend))
    (declare (ignore backend))
    nil))

(defun %normalize-format (format)
  (etypecase format
    (keyword format)
    (symbol (intern (symbol-name format) :keyword))
    (string (intern (string-upcase format) :keyword))))

(defun %media-type-essentials (media-type)
  "Lowercase type/subtype, parameters stripped."
  (let* ((s (string-downcase (string-trim '(#\Space #\Tab #\Return #\Newline)
                                          (etypecase media-type
                                            (string media-type)
                                            (symbol (string media-type))))))
         (semi (position #\; s)))
    (string-trim '(#\Space #\Tab) (if semi (subseq s 0 semi) s))))

(defun %index-media-type (format media-type)
  (let ((key (%media-type-essentials media-type)))
    (when (plusp (length key))
      (setf (gethash key *serdes-media-type-index*) format))))

(defun %apply-default-media-types (format)
  (let ((types (cdr (assoc format *default-media-types* :test #'eq))))
    (when types
      (unless (gethash format *serdes-media-types*)
        (setf (gethash format *serdes-media-types*) (first types)))
      (dolist (mt types)
        (%index-media-type format mt)))))

(defun register-format (format backend &key media-type (binary nil binary-p))
  "Register BACKEND for FORMAT and return BACKEND.
   MEDIA-TYPE is the primary Content-Type (type/subtype). BINARY marks an octet wire."
  (check-type backend serdes-backend)
  (let ((normalized (%normalize-format format)))
    (setf (gethash normalized *serdes-formats*) backend)
    (cond
      (media-type
       (let ((primary (%media-type-essentials media-type)))
         (setf (gethash normalized *serdes-media-types*) primary)
         (%index-media-type normalized primary)))
      (t
       (%apply-default-media-types normalized)))
    (when binary-p
      (setf (gethash normalized *serdes-binary-formats*) binary))
    (unless binary-p
      (when (member normalized *default-binary-formats* :test #'eq)
        (setf (gethash normalized *serdes-binary-formats*) t)))
    backend))

(defun format-media-type (format)
  "Primary MIME type/subtype for FORMAT, or NIL."
  (let ((normalized (%normalize-format format)))
    (or (gethash normalized *serdes-media-types*)
        (let ((backend (find-backend normalized nil)))
          (or (and backend (backend-media-type backend))
              (first (cdr (assoc normalized *default-media-types* :test #'eq))))))))

(defun format-binary-p (format)
  "True when FORMAT's wire form is octets."
  (let ((normalized (%normalize-format format)))
    (or (gethash normalized *serdes-binary-formats*)
        (let ((backend (find-backend normalized nil)))
          (and backend (backend-binary-p backend)))
        (and (member normalized *default-binary-formats* :test #'eq) t))))

(defun find-format-for-media-type (media-type &optional (errorp nil))
  "Format keyword registered for MEDIA-TYPE (parameters ignored), or NIL."
  (let* ((key (%media-type-essentials media-type))
         (format (gethash key *serdes-media-type-index*)))
    (cond
      (format format)
      (errorp
       (error 'serdes-unknown-format
              :format key
              :message (format nil "no serdes format for media type ~S" media-type)))
      (t nil))))

(defun find-backend (format &optional (errorp t))
  "Return the backend registered for FORMAT.
When ERRORP is true, signal SERDES-UNKNOWN-FORMAT when the registry has no backend."
  (let* ((normalized (%normalize-format format))
         (backend (gethash normalized *serdes-formats*)))
    (cond
      (backend backend)
      (errorp
       (error 'serdes-unknown-format
              :format normalized
              :message "load or register a backend for this format"))
      (t nil))))

(defun %backend-for (format)
  (let ((normalized (%normalize-format format)))
    (or (and *serdes-backend*
             (eq normalized (%normalize-format *serdes-format*))
             *serdes-backend*)
        (find-backend normalized))))

(defun %associated-restarts (condition fresh)
  "The active restarts associated with CONDITION (CLHS 9.1.4.2.2) that apply
to it, most recent first. FRESH is a condition that nothing is associated with
yet.
COMPUTE-RESTARTS given CONDITION also returns the restarts associated with no
condition. These are removed: every restart that COMPUTE-RESTARTS returns for
FRESH or for a plain CONDITION made here. A restart associated with CONDITION is
visible for neither of them, so it stays. The one inexact case is a restart
associated with no condition whose test accepts CONDITION and rejects both
probes. It is kept, and so is hidden from other conditions while the caller's
WITH-CONDITION-RESTARTS is in effect."
  (let ((free (append (compute-restarts fresh)
                      (compute-restarts (make-condition 'condition)))))
    (remove-if (lambda (restart) (member restart free :test #'eq))
               (compute-restarts condition))))

(defun %translate-backend-error (condition type format)
  "Signal, with ERROR, a fresh TYPE (SERDES-ENCODE-ERROR or SERDES-DECODE-ERROR)
for CONDITION, an ERROR that is not a SERDES-ERROR and was signalled in the
backend call of ENCODE or DECODE for FORMAT (the argument as given). The new
error's :CAUSE is CONDITION, and the restarts associated with CONDITION are
associated with it too (file header, TRANSLATION). Does not return."
  (let ((e (make-condition type
                           :cause condition
                           :message (format nil "~A failed for ~S: ~A"
                                            (ecase type
                                              (serdes-encode-error "encode")
                                              (serdes-decode-error "decode"))
                                            format condition))))
    (with-condition-restarts e (%associated-restarts condition e)
      (error e))))

(defun encode (value &key stream (format *serdes-format*))
  "Encode VALUE using the backend registered for FORMAT.
Returns a string unless STREAM is supplied. Errors: file header."
  (handler-bind ((error (lambda (c)
                          (unless (typep c 'serdes-error)
                            (%translate-backend-error c 'serdes-encode-error format)))))
    (backend-encode (%backend-for format) value :stream stream)))

(defun decode (source &key (format *serdes-format*))
  "Decode SOURCE using the backend registered for FORMAT. Errors: file header."
  (handler-bind ((error (lambda (c)
                          (unless (typep c 'serdes-error)
                            (%translate-backend-error c 'serdes-decode-error format)))))
    (backend-decode (%backend-for format) source)))

(defun %octet-vector-p (value)
  (and (vectorp value)
       (not (stringp value))
       (let ((et (array-element-type value)))
         (or (equal et '(unsigned-byte 8))
             (subtypep et '(unsigned-byte 8))))))

(defun encode-to-octets (value &key (format *serdes-format*))
  "Octets of VALUE. Binary formats may return octets from ENCODE (passed through);
   text formats are UTF-8 encoded."
  (let ((encoded (encode value :format format)))
    (if (%octet-vector-p encoded)
        encoded
        (babel:string-to-octets encoded :encoding :utf-8))))

(defun decode-octets (octets &key (format *serdes-format*))
  "Decode OCTETS using FORMAT. Backends accept octets or UTF-8 text."
  (decode octets :format format))

(defun %index-all-defaults ()
  (dolist (entry *default-media-types*)
    (dolist (mt (rest entry))
      (%index-media-type (first entry) mt))))

(%index-all-defaults)
