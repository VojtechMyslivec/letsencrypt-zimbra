#!/bin/sh
email=""
sendmail="/usr/sbin/sendmail"
subject="Certificate renewal in $1 day(s)"
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

