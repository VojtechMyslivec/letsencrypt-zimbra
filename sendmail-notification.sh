#!/bin/bash
USAGE="USAGE
    $0 days

    This simple script will send an e-mail to 'email' address via
    'sendmail' program. You must to specify the number of days which
    will be used in the 'reminder_message'.

    The 'email', 'sendmail' and 'reminder_message' are specified
    in letsencrypt-zimbra config file (see main script' help)."

[ $# -ne 1 ] && {
    echo "$USAGE" >&2
    exit 1
}

[[ "$1" =~ ^[0-9]+$ ]] || {
    echo "The first arg '$1' must be a natural number" >&2
    exit 1
}

letsencrypt_zimbra_dir="${0%/*}"
source "$letsencrypt_zimbra_dir/letsencrypt-zimbra.cfg"

echo "Subject: $reminder_subject

$reminder_message" | "$sendmail" "$email"
