(defpackage #:serdes-protocol
  (:use #:cl)
  (:nicknames #:stack-serdes)
  (:export #:serdes-error
           #:serdes-encode-error
           #:serdes-decode-error
           #:serdes-unknown-format
           #:serdes-error-message
           #:serdes-unknown-format-format
           #:serdes-backend
           #:serdes-input-stream
           #:serdes-output-stream
           #:serdes-character-input-stream
           #:serdes-character-output-stream
           #:serdes-binary-input-stream
           #:serdes-binary-output-stream
           #:*serdes-format*
           #:*serdes-backend*
           #:*serdes-formats*
           #:register-format
           #:find-backend
           #:backend-encode
           #:backend-decode
           #:encode
           #:decode
           #:encode-to-octets
           #:decode-octets))

(in-package #:serdes-protocol)
