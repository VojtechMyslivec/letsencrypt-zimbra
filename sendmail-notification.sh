#!/bin/bash
set -o nounset

SCRIPTNAME=${0##*/}

USAGE="USAGE
    $SCRIPTNAME -h | --help | help
    $SCRIPTNAME --success
    $SCRIPTNAME --reminder days

    This simple script will send an e-mail to 'email' address via
    'sendmail' program.

    It will use 'reminder_message' or 'success_message', depending
    on the paramter you used. If you call it with --reminder parameter,
    you must to specify the number of days which will be used in the
    'reminder_message'.

    The 'email', 'sendmail', 'reminder_message' and 'success_message'
    are specified in letsencrypt-zimbra config file (see main script
    help)."

exit_with_usage() {
    echo "$USAGE" >&2
    exit 1
}

# Usage
[ $# -eq 1 -o $# -eq 2 ] || {
    exit_with_usage
}

letsencrypt_zimbra_dir="${0%/*}"
source "$letsencrypt_zimbra_dir/letsencrypt-zimbra.cfg"

case "$1" in
    "-h" | "--help" | "help" )
        echo "$USAGE"
        exit 0
        ;;

    "--success" )
        [ $# -eq 1 ] || {
            exit_with_usage
        }
        subject=$success_subject
        message=$success_message
        ;;

    "--reminder" )
        [ $# -eq 2 ] || {
            exit_with_usage
        }
        [[ "$2" =~ ^[0-9]+$ ]] || {
            echo "days '$2' must be a natural number" >&2
            exit 1
        }
        subject=$reminder_subject
        message=$reminder_message
        ;;

    * )
        echo "$USAGE" >&2
        exit 1
        ;;
esac

echo "Subject: $subject

$message" | cat - # "$sendmail" "$email"
