;;TODO switch sqlite3 command version.

(require 'ert)

(defun sqlite3-test-wait-exit (process)
  (while (eq (process-status process) 'run) (sleep-for 0.01)))

(ert-deftest sqlite3-normal-0001 ()
  :tags '(sqlite3)
  (let* ((db (make-temp-file "sqlite3-test-"))
         (stream (sqlite3-stream-open db)))
    (unwind-protect
        (progn
          (should (sqlite3-stream-execute-sql stream "CREATE TABLE hoge (id INTEGER PRIMARY KEY, text TEXT)"))
          (should (equal (sqlite3-read-table-schema stream "hoge")
                         '((0 "id" "INTEGER" nil :null t) (1 "text" "TEXT" nil :null nil))))
          (should (sqlite3-stream-execute-sql stream "INSERT INTO hoge VALUES (1, 'a')"))
          (should (sqlite3-stream-execute-sql stream "INSERT INTO hoge VALUES (2, 'b')"))
          (should (equal (sqlite3-stream-read-query
                          stream "SELECT * FROM hoge ORDER BY id")
                         '(("1" "a") ("2" "b"))))
          (should (sqlite3-stream-execute-sql stream "UPDATE hoge SET id = id + 10, text = text || 'z'"))
          (should (equal
                   (sqlite3-stream-read-query stream "SELECT * FROM hoge")
                   '(("11" "az") ("12" "bz"))))
          (should (sqlite3-stream-execute-sql stream "DELETE FROM hoge WHERE id = 11"))
          (should (equal
                   (sqlite3-stream-read-query stream "SELECT * FROM hoge")
                   '(("12" "bz"))))
          (should (sqlite3-stream-execute-sql stream "INSERT INTO hoge VALUES(3, 'あイｳ')"))
          (should (equal
                   (sqlite3-stream-read-query stream "SELECT text FROM hoge WHERE id = 3")
                   '(("あイｳ"))))
          )
      (sqlite3-stream-close stream)
      (delete-file db))))

(ert-deftest sqlite3-irregular-0001 ()
  :tags '(sqlite3)
  (let* ((db (make-temp-file "sqlite3-test-"))
         (stream (sqlite3-stream-open db)))
    (unwind-protect
        (progn
          (sqlite3-stream-execute-sql stream "CREATE TABLE hoge (id INTEGER PRIMARY KEY)")
          (should-error (sqlite3-stream-execute-sql stream "CREATE TABLE1"))
          (should-error (sqlite3-stream-execute-sql stream "CREATE TABLE hoge (id INTEGER PRIMARY KEY)"))
          (sqlite3-stream-execute-sql stream "INSERT INTO hoge VALUES (1)")
          (should-error (sqlite3-stream-execute-sql stream "INSERT INTO hoge VALUES (1)"))
          (should (equal (sqlite3-stream-read-query stream "SELECT * FROM hoge") '(("1"))))
          (should-error (sqlite3-stream-read-query stream "SELECT"))
          ;; works fine after syntax error
          (should (equal (sqlite3-stream-read-query stream "SELECT * FROM hoge") '(("1")))))
      (sqlite3-stream-close stream))))

(ert-deftest sqlite3-async-read ()
  :tags '(sqlite3)
  (let ((db (make-temp-file "sqlite3-test-")))
    (unwind-protect
        (progn
          (sqlite3-async-read db "CREATE TABLE hoge (id);" (lambda (x)))
          (let ((query (mapconcat
                        'identity
                        (mapcar
                         (lambda (n)
                           (format "INSERT INTO hoge VALUES(%d);" n))
                         '(1 2 3 4 5)) "")))
            (sqlite3-async-read db query (lambda (x)))
            (let ((result '()))
              (sqlite3-async-read
               db "SELECT id FROM hoge;"
               (lambda (x)
                 (unless (eq x :EOF)
                   (setq result (cons (string-to-number (nth 0 x)) result)))))
              (should (equal '(5 4 3 2 1) result)))
            (should-error (sqlite3-async-read db "SELECT" (lambda (x))))))
      (delete-file db))))

(ert-deftest sqlite3-read ()
  :tags '(sqlite3)
  (let ((db (make-temp-file "sqlite3-test-")))
    (unwind-protect
        (progn
          (sqlite3-read db "CREATE TABLE hoge (id, text);")
          (sqlite3-read db "INSERT INTO hoge VALUES (1, 'あイｳ');")
          (should (equal (sqlite3-read db "SELECT text FROM hoge WHERE id = 1")
                         '(("あイｳ"))))
          (should-error (sqlite3-read db "SELECT")))
      (delete-file db))))

;;TODO reader test
;;TODO sqlite3-call/

(ert-deftest sqlite3-escape ()
  :tags '(sqlite3)
  (should (equal "A" (sqlite3-escape-string "A") ))
  (should (equal "A''''" (sqlite3-escape-string "A''")))
  (should (equal "A''\"" (sqlite3-escape-string "A'\"")))
  (should (equal "A'\"\"" (sqlite3-escape-string "A'\"" ?\")))
  (should (equal "A" (sqlite3-escape-like "A" ?\\)))
  (should (equal "A\\%\\_" (sqlite3-escape-like "A%_" ?\\)))
  (should (equal "\\\\\\%\\\\\\_" (sqlite3-escape-like "\\%\\_" ?\\))))

(ert-deftest sqlite3-glob-to-like ()
  :tags '(sqlite3)
  (should (equal "a" (sqlite3-helm-glob-to-like "a")))
  (should (equal "%ab_" (sqlite3-helm-glob-to-like "*ab?")))
  (should (equal "\\_a" (sqlite3-helm-glob-to-like "_a" ?\\)))
  (should (equal "*?%_\\%\\_" (sqlite3-helm-glob-to-like "\\*\\?*?\\%\\_" ?\\)))
  (should (equal "*0\\%" (sqlite3-helm-glob-to-like "\\*0%" ?\\)))
  (should (equal "\\0|%||" (sqlite3-helm-glob-to-like "\\\\0%|" ?\|)))
  (should (equal "\\\\0\\%|" (sqlite3-helm-glob-to-like "\\\\0%|" ?\\))))

(ert-deftest sqlite3-fuzzy-glob-to-like ()
  :tags '(sqlite3)
  (should (equal "a%" (sqlite3-helm-fuzzy-glob-to-like "^a")))
  (should (equal "%a%" (sqlite3-helm-fuzzy-glob-to-like "a")))
  (should (equal "%a" (sqlite3-helm-fuzzy-glob-to-like "a$")))
  (should (equal "%^a%" (sqlite3-helm-fuzzy-glob-to-like "\\^a")))
  (should (equal "%a$%" (sqlite3-helm-fuzzy-glob-to-like "a\\$")))
  (should (equal "%a\\\\" (sqlite3-helm-fuzzy-glob-to-like "a\\\\$")))
  )

(ert-deftest sqlite3-format ()
  :tags '(sqlite3)
  ;;TODO error test

  (should (equal
           (let ((search-text "hoge"))
             (sqlite3-format
              "SELECT %O,%o,%T,%V FROM %o WHERE %o LIKE %L{search-text} AND col2 IN (%V)"
              '("a" "b")
              "c" "'text"
              "something"
              "table"
              "d" '("foo" 1)))
           (concat
            "SELECT "
            "\"a\", \"b\",\"c\",'''text','something'"
            " FROM \"table\""
            " WHERE"
            " \"d\" LIKE 'hoge' ESCAPE '\\' "
            " AND col2 IN ('foo', 1)")))
  (should (equal
           (sqlite3-format
            '(
              "INSERT INTO (%O)"
              " VALUES (%V) ")
            '("a" "b") '("1" 2))
           (concat
            "INSERT INTO (\"a\", \"b\")\n"
            " VALUES ('1', 2) "))))
