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
           #:underlying-stream
           #:stream-backend
           #:*serdes-format*
           #:*serdes-backend*
           #:*serdes-formats*
           #:register-format
           #:find-backend
           #:backend-encode
           #:backend-decode
           #:backend-media-type
           #:backend-binary-p
           #:format-media-type
           #:format-binary-p
           #:find-format-for-media-type
           #:encode
           #:decode
           #:encode-to-octets
           #:decode-octets
           #:backend-make-input-stream
           #:backend-make-output-stream
           #:make-input-stream
           #:make-output-stream
           #:stream-encode-value
           #:stream-decode-value
           #:map-jsonl
           #:do-jsonl
           #:serdes-event-parser
           #:event-parser-backend
           #:event-parser-source
           #:backend-make-event-parser
           #:parse-next-event
           #:parse-next-element
           #:make-event-parser
           #:with-event-parser
           #:map-events))

(in-package #:serdes-protocol)
