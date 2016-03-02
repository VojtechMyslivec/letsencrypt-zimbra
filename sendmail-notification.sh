#!/bin/bash
email=""
mail="/usr/bin/mail"
subject="Certificate renewal in $1 day(s)"
message="Hello,
this is just a kindly reminder that a letsencrypt-gitlab tool
will try to obtain and install new gitlab certificate in $1 day(s).

Sincerelly yours,
cron"

USAGE="USAGE
    $0 days

    This simple script will send the email to e-mail '$email' via
    '$sendmail' program. You must to specify the number of days in
    the message: 'message'."

[ $# -ne 1 ] && {
    echo "$USAGE" >&2
    exit 1
}

[[ "$1" =~ ^[0-9]+$ ]] || {
    echo "The first arg '$1' must be a natural number" >&2
    exit 1
}


echo "$message" | "$mail" -s "$subject" "$email"

