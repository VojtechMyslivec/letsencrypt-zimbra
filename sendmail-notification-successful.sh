#!/bin/sh
email=""
sendmail="/opt/zimbra/postfix/sbin/sendmail"
subject="Certificate has been renewed"
message="Hello,
this is just a kindly reminder that a letsencrypt-zimbra tool
renewed successfully your Zimbra certificate!

Sincerelly yours,
cron"

USAGE="USAGE
    $0

    This simple script will send the email to e-mail '$email' via
    '$sendmail' program."

[ $# -ne 0 ] && {
    echo "$USAGE" >&2
    exit 1
}

echo "Subject: $subject

$message" | "$sendmail" "$email"

