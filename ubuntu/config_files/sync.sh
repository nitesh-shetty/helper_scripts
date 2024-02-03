getmail
lei up lkml_dir/mail
notmuch new
notmuch tag --batch --input=lkml_dir/notmuch-tag-rules
notmuch tag --remove-all +deleted tag:deleted
