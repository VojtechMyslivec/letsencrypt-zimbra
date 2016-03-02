#!/bin/sh
email=""
mail="/usr/bin/mail"
subject="Certificate has been renewed"
message="Hello,
this is just a kindly reminder that a letsencrypt-gitlab tool
renewed successfully your gitlab certificate!

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

echo "$message" | "$mail" -s "$subject" "$email"

