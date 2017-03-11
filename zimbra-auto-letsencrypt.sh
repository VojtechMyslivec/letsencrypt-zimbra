#!/bin/bash
# credit for original script Vojtech Myslivec <vojtech@xmyslivec.cz>
# https://github.com/VojtechMyslivec/letsencrypt-zimbra
# GPLv2 licence

# fork author: Lorenzo Faleschini <lorenzo@nordest.systems>
# https://github.com/penzoiders/letsencrypt-zimbra

SCRIPTNAME=${0##*/}

USAGE="USAGE

    IMPORTANT NOTE:
    if running from the shell you must cd to the script directory
    if running from crontab you *must* pass the config path as
    argument

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
    them once the certificate is generated/renewed and deployed. If the
    obtained certificate isn't valid after all, Zimbra will start
    with the old certificate unchanged.

    Suitable to be run via cron (you need to pass the config file path
    to succesfully source the variables)
    
    Crontab example for autorenewal:

# send a notification a week before the certificate will be obtained
0 0 1 */2 * /root/zimbra-auto-letsencrypt/sendmail-notification.sh 7 your@email.com >/dev/null 2>&1
# send a notification a day before the certificate will be obtained
0 0 7 */2 * /root/zimbra-auto-letsencrypt/sendmail-notification.sh 1 your@email.com >/dev/null 2>&1
# obtain the certificate
0 0 8 */2 * /root/zimbra-auto-letsencrypt/zimbra-auto-letsencrypt.sh --renew /root/zimbra-auto-letsencrypt/letsencrypt-zimbra.conf && /root/zimbra-auto-letsencrypt/sendmail-notification-successful.sh your@email.com >/dev/null 2>&1

    Friendly notice: 
    restarting Zimbra service take a while (1+ m).

    Depends on:
        zimbra
        certbot
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
	if [ -n "$2" ]; then
            config_file="$2"
        fi
    else
        exit 1
    fi
}


# source the variables file
source  "$config_file"

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
        exit 3
    }
}

# and another one to start it
start_nginx() {
    su -c 'zmproxyctl start; zmmailboxdctl start' - "$zimbra_user" || {
        error "There were some error during starting the Zimbra' nginx."
        fix_nginx_message
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

if [ $renew_cert = "yes" ]; then

  readable_file "$letsencrypt_issued_key_file" || {
    error "Private key '$letsencrypt_issued_key_file' isn't readable file."
    exit 2
  }

  readable_file "$letsencrypt_issued_cert_file" || {
    error "Certificate '$letsencrypt_issued_cert_file' isn't readable file."
    exit 2
  }

  readable_file "$letsencrypt_issued_chain_file" || {
    error "Intermediate CA '$letsencrypt_issued_chain_file' isn't readable file."
        exit 2
  }

  readable_file "$letsencrypt_issued_fullchain_file" || {
    error "Certificate bundle '$letsencrypt_issued_fullchain_file' isn't readable file."
        exit 2
  }

fi

readable_file "$root_CA_file" || {
    error "The root CA certificate '$root_CA_file' isn't readable file."
    exit 2
}


# --------------------------------------------------------------------
# -- Obtaining the certificate ---------------------------------------
# --------------------------------------------------------------------

# release the 443 port -- stop Zimbra' nginx
    stop_nginx


if [ "$renew_cert" == "no" ]; then
    
    # generate a new certificate
    "$letsencrypt" certonly --standalone --agree-tos --text --email "$letsencrypt_email" -d "$CN"  || {
        error "The certificate cannot be obtained with '$letsencrypt' tool."
        start_nginx
        exit 4
    }
   
else

    # renew the certificate
    "$letsencrypt" renew --renew-by-default

fi

# start Zimbra' nginx again
start_nginx

# --------------------------------------------------------------------
# -- Deploying the certificate ---------------------------------------
# --------------------------------------------------------------------

su -c "cp -r /opt/zimbra/ssl/zimbra /opt/zimbra/ssl/zimbra.'$(date +%Y%m%d)'" - "$zimbra_user"

cat "$letsencrypt_issued_key_file" > /opt/zimbra/ssl/zimbra/commercial/commercial.key
cat "$letsencrypt_issued_cert_file" > /tmp/commercial.crt 
cat "$root_CA_file" "$letsencrypt_issued_chain_file" > /tmp/commercial_ca.crt 

chown -R "$zimbra_user":"$zimbra_user" /opt/zimbra/ssl/zimbra/commercial/commercial.key
chown -R "$zimbra_user":"$zimbra_user" /tmp/commercial.crt
chown -R "$zimbra_user":"$zimbra_user" /tmp/commercial_ca.crt

# verify it with Zimbra tool
su -c "'$zmcertmgr' verifycrt comm /opt/zimbra/ssl/zimbra/commercial/commercial.key /tmp/commercial.crt /tmp/commercial_ca.crt" - "$zimbra_user" || {
    error "Verification of the issued certificate with '$zmcertmgr' failed."
    exit 4
}

# install the certificate to Zimbra
su -c "'$zmcertmgr' deploycrt comm /tmp/commercial.crt /tmp/commercial_ca.crt" - "$zimbra_user" || {
    error "Installation of the issued certificate with '$zmcertmgr' failed."
    exit 4
}


# finally, restart Zimbra
service "$zimbra_service" restart || {
    error "Restarting zimbra service failed."
    exit 5
}


