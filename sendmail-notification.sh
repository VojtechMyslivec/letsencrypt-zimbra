#!/bin/bash
email="$2"
sendmail="/opt/zimbra/common/sbin/sendmail"
subject="Certificate renewal in $1 day(s)"
message="Hello,
this is just a kindly reminder that a letsencrypt-zimbra tool
will try to obtain and install new zimbra certificate in $1 day(s).

Sincerelly yours,
cron"

USAGE="USAGE
    $0 days email_address

    This simple script will send the email to the specified 
    e-mail address via '$sendmail' program."

[ $# -ne 2 ] && {
    echo "$USAGE" >&2
    exit 1
}

[[ "$1" =~ ^[0-9]+$ ]] || {
    echo "The first arg '$1' must be a natural number" >&2
    exit 1
}

[ $# -eq 1 ] && {
    if [ "$1" == "-h" -o "$1" == "--help" -o "$1" == "help" ]; then
    echo "$USAGE" >&2
    exit 1
    fi
}

echo "Subject: $subject

$message" | "$sendmail" "$email"

