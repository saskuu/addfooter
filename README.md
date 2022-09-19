# addfooter
add footer to email in postfix


/etc/postfix/master.cf

    smtpd      pass  -       -       n       -       -       smtpd
      -o content_filter=addfooter:dummy
    
    smtps    inet  n       -       n       -       -       smtpd
      -o content_filter=addfooter:dummy
    
    addfooter unix  -       n       n       -       20      pipe
      flags=Rq user=nobody argv=/opt/postfix/addfooter.pl -f ${sender} -- ${recipient}

Debug
- ./addfolder < mail > newmail
