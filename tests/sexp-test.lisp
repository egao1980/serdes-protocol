(in-package #:serdes-protocol/tests)

(defun sample-hash ()
  (let ((table (make-hash-table :test #'equal)))
    (setf (gethash "msg" table) "hello"
          (gethash "null" table) :null
          (gethash "items" table) #(1 2 3))
    table))

(deftest sexp-hash-roundtrip
  (sexp-protocol:use-sexp-backend)
  (let* ((encoded (encode (sample-hash) :format :sexp))
         (decoded (decode encoded :format :sexp)))
    (ok (search "hello" encoded))
    (ok (hash-table-p decoded))
    (ok (string= "hello" (gethash "msg" decoded)))
    (ok (eq :null (gethash "null" decoded)))
    (ok (equalp #(1 2 3) (gethash "items" decoded)))))

(deftest sexp-plist-to-hash
  (sexp-protocol:use-sexp-backend)
  (let ((decoded (decode (encode '(:msg "hello" :ok t :null :null) :format :sexp)
                         :format :sexp)))
    (ok (hash-table-p decoded))
    (ok (string= "hello" (gethash "msg" decoded)))
    (ok (eq t (gethash "ok" decoded)))
    (ok (eq :null (gethash "null" decoded)))))

(deftest sexp-octets
  (sexp-protocol:use-sexp-backend)
  (let* ((octets (encode-to-octets '(:msg "octets") :format :sexp))
         (decoded (decode-octets octets :format :sexp)))
    (ok (typep octets '(vector (unsigned-byte 8))))
    (ok (string= "octets" (gethash "msg" decoded)))))
