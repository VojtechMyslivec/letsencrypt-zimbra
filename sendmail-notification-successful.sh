#!/bin/bash
USAGE="USAGE
    $0

    This simple script will send an e-mail to 'email' address via
    'sendmail' program.

    The 'email' and 'sendmail' are specified in letsencrypt-zimbra
    config file (see main script' help)."

[ $# -ne 0 ] && {
    echo "$USAGE" >&2
    exit 1
}

letsencrypt_zimbra_dir="${0%/*}"
source "$letsencrypt_zimbra_dir/letsencrypt-zimbra.cfg"

echo "Subject: $success_subject

$success_message" | "$sendmail" "$email"
