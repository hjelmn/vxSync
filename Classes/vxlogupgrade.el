(defun vxlogupgrade ()
  (interactive)
  (while (re-search-forward "vxSync_log2 (,,,);"
  (while (search-forward "vxSync_log2" nil t)
    (when (save-excursion
	    (forward-line 0)
	    (search-forward "log" (line-end-position) t))
      (backward-char 2)
      (while (search-forward "%@" (line-end-position) t)
	(if (save-match-data (y-or-n-p "%s it? ")) (replace-match "%s")))
      (while (search-forward "," (line-end-position) t)
	(skip-syntax-forward " ")
	(looking-at "[^,)]+")
	(if (save-match-data (y-or-n-p "NS2CH it? ")) (replace-match "NS2CH(\\&)")))))
  (message "ns2ch: done."))

