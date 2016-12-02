#!/bin/bash
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

letsencrypt_zimbra_dir="${0%/*}"
source "$letsencrypt_zimbra_dir/letsencrypt-zimbra.cfg"

echo "Subject: $subject

$message" | "$sendmail" "$email"

