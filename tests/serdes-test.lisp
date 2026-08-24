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
  (register-format :test-bin (make-instance 'octet-backend))
  (let ((octets (encode-to-octets #(1 2 3) :format :test-bin)))
    (ok (equalp #(1 2 3) octets))
    (ok (equalp #(1 2 3) (decode-octets octets :format :test-bin)))))
