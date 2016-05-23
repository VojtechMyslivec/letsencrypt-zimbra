#!/bin/bash
# author: Vojtech Myslivec <vojtech@xmyslivec.cz>
# GPLv2 licence

SCRIPTNAME=${0##*/}

USAGE="USAGE
    $SCRIPTNAME -h | --help | help
    $SCRIPTNAME

    This script is used for extend the already-deployed zimbra
    (so-called) commercial certificate issued by Let's Encrypt
    certification authority.

    The script will stop zimbra' services for a while and restart
    them once the certificate is extended and deployed. If the
    obtained certificate isn't valid after all, Zimbra will start
    with the old certificate unchanged.

    Suitable to be run via cron.

    Friendly notice: restarting Zimbra service take a while (1+ m).

    Depends on:
        zimbra
        letsencrypt-auto utility
        openssl"

# --------------------------------------------------------------------
# -- Variables -------------------------------------------------------
# --------------------------------------------------------------------
# should be in config file o_O

# letsencrypt tool
letsencrypt="/root/letsencrypt/letsencrypt-auto"
# the name of file which letsencrypt will generate
letsencrypt_issued_cert_file="0000_cert.pem"
# intermediate CA
letsencrypt_issued_intermediate_CA_file="0000_chain.pem"
# root CA
root_CA_file="/root/letsencrypt-zimbra/DSTRootCAX3.pem"

zimbra_service="zimbra"
zimbra_user="zimbra"
zimbra_dir="/opt/zimbra"

zimbra_bin_dir="${zimbra_dir}/bin"
zmcertmgr="${zimbra_bin_dir}/zmcertmgr"

zimbra_ssl_dir="${zimbra_dir}/ssl/zimbra/commercial"
zimbra_key="${zimbra_ssl_dir}/commercial.key"

# common name in the certificate
CN="mail.theajty.com"
# subject in request -- does not matter for letsencrypt but must be there for openssl
cert_subject="/"
# openssl config skeleton
#  it is important to have an alt_names section there!
openssl_config="
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]
[ v3_req ]

basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $CN
"

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
    su -c 'zmproxyctl stop; zmmailboxdctl stop' - "$zimbra_user" > /dev/null || {
        error "There were some error during stopping the Zimbra' nginx."
        fix_nginx_message
        cleanup
        exit 3
    }
}

# and another one to start it
start_nginx() {
    su -c 'zmproxyctl start; zmmailboxdctl start' - "$zimbra_user" > /dev/null || {
        error "There were some error during starting the Zimbra' nginx."
        fix_nginx_message
        cleanup
        exit 3
    }
}

# --------------------------------------------------------------------
# -- Usage -----------------------------------------------------------
# --------------------------------------------------------------------

# HELP?
[ $# -eq 1 ] && {
    if [ "$1" == "-h" -o "$1" == "--help" -o "$1" == "help" ]; then
        echo "$USAGE"
        exit 0
    fi
}

[ $# -eq 0 ] || {
    echo "$USAGE" >&2
    exit 1
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

readable_file "$zimbra_key" || {
    error "Private key '$zimbra_key' isn't readable file."
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
openssl_config_file="${temp_dir}/openssl.cnf"
request_file="${temp_dir}/request.pem"

# create the openssl config file
echo "$openssl_config" > "$openssl_config_file"

# --------------------------------------------------------------------
# -- Obtaining the certificate ---------------------------------------
# --------------------------------------------------------------------

# create the certificate signing request [crs]
openssl req -new -nodes -sha256 -outform der \
    -config "$openssl_config_file" \
    -subj "$cert_subject" \
    -key "$zimbra_key" \
    -out "$request_file" || {
    error "Cannot create the certificate signing request."
    cleanup
    exit 3
}

# release the 443 port -- stop Zimbra' nginx
stop_nginx

# ----------------------------------------------------------
# letsencrypt utility stores the obtained certificates in PWD,
# so we must cd in the temp directory
cd "$temp_dir"

"$letsencrypt" certonly --standalone --csr "$request_file" > /dev/null 2>&1 || {
    error "The certificate cannot be obtained with '$letsencrypt' tool."
    start_nginx
    cleanup
    exit 4
}

# cd back -- which is not really neccessarry
cd - > /dev/null
# ----------------------------------------------------------

# start Zimbra' nginx again
start_nginx


# --------------------------------------------------------------------
# -- Deploying the certificate ---------------------------------------
# --------------------------------------------------------------------

cert_file="${temp_dir}/${letsencrypt_issued_cert_file}"
intermediate_CA_file="${temp_dir}/${letsencrypt_issued_intermediate_CA_file}"
chain_file="${temp_dir}/chain.pem"

readable_file "$cert_file" || {
    error "The issued certificate file '$cert_file' isn't readable file. Maybe it was created with different name?"
    cleanup
    exit 4
}

readable_file "$intermediate_CA_file" || {
    error "The issued intermediate CA file '$intermediate_CA_file' isn't readable file. Maybe it was created with different name?"
    cleanup
    exit 4
}

# create one CA chain file
cat "$root_CA_file" "$intermediate_CA_file" > "$chain_file"

# verify it with Zimbra tool
"$zmcertmgr" verifycrt comm "$zimbra_key" "$cert_file" "$chain_file" > /dev/null || {
    error "Verification of the issued certificate with '$zmcertmgr' failed."
    exit 4
}

# install the certificate to Zimbra
"$zmcertmgr" deploycrt comm "$cert_file" "$chain_file" > /dev/null || {
    error "Installation of the issued certificate with '$zmcertmgr' failed."
    exit 4
}


# finally, restart the Zimbra
service "$zimbra_service" restart > /dev/null || {
    error "Restarting zimbra service failed."
    exit 5
}


# --------------------------------------------------------------------
# -- Cleanup ---------------------------------------------------------
# --------------------------------------------------------------------

cleanup

