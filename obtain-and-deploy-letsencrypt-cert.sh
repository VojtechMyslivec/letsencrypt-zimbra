#!/bin/bash
# credit for original script Vojtech Myslivec <vojtech@xmyslivec.cz>
# https://github.com/VojtechMyslivec/letsencrypt-zimbra
# GPLv2 licence

# fork author: Lorenzo Faleschini <lorenzo@nordest.systems>
# https://github.com/penzoiders/letsencrypt-zimbra

SCRIPTNAME=${0##*/}

USAGE="USAGE
    print this help:
    $SCRIPTNAME -h | --help | help

    get and deploy the certificate:
    $SCRIPTNAME
    get and deploy the certificate passing a custom config file:
    $SCRIPTNAME /path/to/letsencrypt-zimbra.conf
    
    renew the certificate:
    $SCRIPTNAME --renew
    renew the certificate passing  a custom config file:
    $SCRIPTNAME --renew /path/to/letsencrypt-zimbra.conf

    This script is used to generate/renew and deploy zimbra
    (so-called) commercial certificate by using Let's Encrypt
    certification authority.

    The script will stop zimbra' services for a while and restart
    them once the certificate is extended and deployed. If the
    obtained certificate isn't valid after all, Zimbra will start
    with the old certificate unchanged.

    Suitable to be run via cron (you need to pass the config file path
    to succesfully source the variables
    
    Crontab example for autorenewal:

    # send a notification a week before the certificate will be obtained
    0 0 1 */2 * root /root/letsencrypt-zimbra/sendmail-notification.sh 7
    # send a notification a day before the certificate will be obtained
    0 0 7 */2 * root /root/letsencrypt-zimbra/sendmail-notification.sh 1
    # obtain the certificate
    0 0 8 */2 * root /root/letsencrypt-zimbra/obtain-and-deploy-letsencrypt-cert.sh --renew /root/letsencrypt-zimbra/letsencrypt-zimbra.conf && /root/letsencrypt-zimbra/sendmail-notification-successful.sh

    Friendly notice: restarting Zimbra service take a while (1+ m).

    Depends on:
        zimbra
        letsencrypt-auto utility
        openssl"

# --------------------------------------------------------------------
# -- Setting default variables ---------------------------------------
# --------------------------------------------------------------------

# use default config file if nothing is declared
config_file="letsencrypt-zimbra.conf"

# generating a new certificate by default if the --renew is not passed
renew_cert="no"

# --------------------------------------------------------------------
# -- Get parameters and source variables -----------------------------
# --------------------------------------------------------------------

# single argument case: help, renew o custom config file
[ $# -eq 1 ] && {
    if [ "$1" == "-h" -o "$1" == "--help" -o "$1" == "help" ]; then
        echo "$USAGE"
        exit 0
    fi
    if [ "$1" == "--renew" ]; then
        renew_cert="yes"
    fi
    if [ -n "$1" ]; then
        config_file="$1"
    fi
}

# double argument: renew and config
[ $# -eq 2 ] && {
    if [ "$1" == "--renew" ]; then
        renew_cert="yes"
	if [ -z "$2" ]; then
            config_file="$2"
        fi
    else
        exit 1
    fi
}


# source the variables file
.  "$config_file"

# --------------------------------------------------------------------
# -- Functions -------------------------------------------------------
# --------------------------------------------------------------------
# common message format, called by error, warning, information, ...
#  $1 - level
#  $2 - message

message() {
    echo "$SCRIPTNAME[$1]: $2" >&2
}

error() {
    message "err" "$*"
}

warning() {
    message "warn" "$*"
}

information() {
    message "info" "$*"
}

readable_file() {
    [ -f "$1" -a -r "$1" ]
}

executable_file() {
    [ -f "$1" -a -x "$1" ]
}

cleanup() {
    [ -d "$temp_dir" ] && {
        rm -rf "$temp_dir" || {
            warning "Cannot remove temporary directory '$temp_dir'. You should check it for private data."
        }
    }
}

# just a kindly message how to fix stopped nginx
fix_nginx_message() {
    echo "        You must probably fix it with:
        'su -c 'zmproxyctl start; zmmailboxdctl start' - $zimbra_user'
        command or something." >&2
}

# this function will stop Zimbra's nginx
stop_nginx() {
    su -c 'zmproxyctl stop; zmmailboxdctl stop' - "$zimbra_user" || {
        error "There were some error during stopping the Zimbra' nginx."
        fix_nginx_message
        cleanup
        exit 3
    }
}

# and another one to start it
start_nginx() {
    su -c 'zmproxyctl start; zmmailboxdctl start' - "$zimbra_user" || {
        error "There were some error during starting the Zimbra' nginx."
        fix_nginx_message
        cleanup
        exit 3
    }
}


# --------------------------------------------------------------------
# -- Tests -----------------------------------------------------------
# --------------------------------------------------------------------

executable_file "$letsencrypt" || {
    error "Letsencrypt tool '$letsencrypt' isn't executable file."
    exit 2
}

executable_file "$zmcertmgr" || {
    error "Zimbra cert. manager '$zmcertmgr' isn't executable file."
    exit 2
}

readable_file "$letsencrypt_issued_key_file" || {
    error "Private key '$letsencrypt_issued_key_file' isn't readable file."
    exit 2
}

readable_file "$root_CA_file" || {
    error "The root CA certificate '$root_CA_file' isn't readable file."
    exit 2
}

# --------------------------------------------------------------------
# -- Temporary files -------------------------------------------------
# --------------------------------------------------------------------

temp_dir=$( mktemp -d ) || {
    error "Cannot create temporary directory."
    exit 2
}


# --------------------------------------------------------------------
# -- Obtaining the certificate ---------------------------------------
# --------------------------------------------------------------------

if [ "$renew_cert" == "no" ]; then
    
    # release the 443 port -- stop Zimbra' nginx
    stop_nginx
    
    # ----------------------------------------------------------
    # letsencrypt utility stores the obtained certificates in PWD,
    # so we must cd in the temp directory
    
    "$letsencrypt" certonly --standalone --agree-tos --text --email "$letsencrypt_email" -d "$CN"  || {
        error "The certificate cannot be obtained with '$letsencrypt' tool."
        start_nginx
        cleanup
        exit 4
    }
    
    # cd  back -- which is not really neccessarry
    cd - > /dev/null
    # ----------------------------------------------------------
    
    # start Zimbra' nginx again
    start_nginx
else
    "$letsencrypt" renew --renew-by-default
fi

# --------------------------------------------------------------------
# -- Deploying the certificate ---------------------------------------
# --------------------------------------------------------------------

cp $letsencrypt_issued_key_file "$temp_dir/privkey.pem"
cp $letsencrypt_issued_cert_file "$temp_dir/cert.pem"
cat "$root_CA_file" "$letsencrypt_issued_chain_file" > "${temp_dir}/zimbra_chain.pem"
chown -R "$zimbra_user":"$zimbra_user" $temp_dir

zimbra_cert_file="$temp_dir/cert.pem"
zimbra_chain_file="$temp_dir/zimbra_chain.pem"
zimbra_key_file="$temp_dir/privkey.pem"


readable_file "$letsencrypt_issued_chain_file" || {
    error "The issued intermediate CA file '$letsencrypt_issued_chain_file' isn't readable file. Maybe it was created with different name?"
    cleanup
    exit 4
}

# verify it with Zimbra tool
su -c "'$zmcertmgr' verifycrt comm '$zimbra_key_file' '$zimbra_cert_file' '$zimbra_chain_file'" - "$zimbra_user" || {
    error "Verification of the issued certificate with '$zmcertmgr' failed."
    exit 4
}

# install the certificate to Zimbra
su -c "'$zmcertmgr' deploycrt comm '$zimbra_cert_file' '$zimbra_chain_file'" - "$zimbra_user" || {
    error "Installation of the issued certificate with '$zmcertmgr' failed."
    exit 4
}


# finally, restart the Zimbra
service "$zimbra_service" restart || {
    error "Restarting zimbra service failed."
    exit 5
}


# --------------------------------------------------------------------
# -- Cleanup ---------------------------------------------------------
# --------------------------------------------------------------------

cleanup

