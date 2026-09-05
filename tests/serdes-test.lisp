(in-package #:serdes-protocol/tests)

(deftest unknown-format-condition
  (let ((condition (handler-case
                       (progn (encode "x" :format :missing) nil)
                     (serdes-unknown-format (e) e))))
    (ok (typep condition 'serdes-unknown-format))
    (ok (eq :missing (serdes-unknown-format-format condition)))))

(defclass octet-backend (serdes-backend) ())

(defmethod backend-encode ((backend octet-backend) value &key stream)
  (declare (ignore backend stream))
  (coerce value '(vector (unsigned-byte 8))))

(defmethod backend-decode ((backend octet-backend) source &key)
  (declare (ignore backend))
  source)

(deftest binary-octets-passthrough
  (register-format :test-bin (make-instance 'octet-backend) :binary t
                   :media-type "application/octet-stream")
  (let ((octets (encode-to-octets #(1 2 3) :format :test-bin)))
    (ok (equalp #(1 2 3) octets))
    (ok (equalp #(1 2 3) (decode-octets octets :format :test-bin)))
    (ok (format-binary-p :test-bin))
    (ok (string= "application/octet-stream" (format-media-type :test-bin)))
    (ok (eq :test-bin (find-format-for-media-type "application/octet-stream; charset=bin")))))

(deftest default-media-types
  (ok (string= "application/json" (format-media-type :json)))
  (ok (eq :json (find-format-for-media-type "application/json")))
  (ok (eq :json (find-format-for-media-type "text/json; charset=utf-8")))
  (ok (eq :cbor (find-format-for-media-type "application/cbor")))
  (ok (eq :messagepack (find-format-for-media-type "application/msgpack")))
  (ok (eq :avro (find-format-for-media-type "avro/binary")))
  (ok (eq :mime (find-format-for-media-type "message/rfc822")))
  (ok (eq :multipart (find-format-for-media-type "multipart/form-data")))
  (ok (format-binary-p :cbor))
  (ok (string= "application/cbor" (format-media-type :cbor))))
