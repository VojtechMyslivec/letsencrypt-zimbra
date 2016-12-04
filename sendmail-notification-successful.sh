#!/bin/sh
USAGE="USAGE
    $0

    This simple script will send the email to e-mail '$email' via
    '$sendmail' program."

[ $# -ne 0 ] && {
    echo "$USAGE" >&2
    exit 1
}

letsencrypt_zimbra_dir="${0%/*}"
source "$letsencrypt_zimbra_dir/letsencrypt-zimbra.cfg"

echo "Subject: $subject

$message" | "$sendmail" "$email"

