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

(defun encode (value &key stream (format *serdes-format*))
  "Encode VALUE using the backend registered for FORMAT.
Returns a string unless STREAM is supplied."
  (handler-case
      (backend-encode (%backend-for format) value :stream stream)
    (serdes-error (e) (error e))
    (error (e)
      (error 'serdes-encode-error
             :message (format nil "encode failed for ~S: ~A" format e)))))

(defun decode (source &key (format *serdes-format*))
  "Decode SOURCE using the backend registered for FORMAT."
  (handler-case
      (backend-decode (%backend-for format) source)
    (serdes-error (e) (error e))
    (error (e)
      (error 'serdes-decode-error
             :message (format nil "decode failed for ~S: ~A" format e)))))

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
