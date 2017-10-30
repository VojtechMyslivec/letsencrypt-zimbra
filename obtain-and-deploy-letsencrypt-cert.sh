#!/bin/bash
## letsencrypt-zimbra
#
# Author:   Vojtech Myslivec <vojtech@xmyslivec.cz>
#           and others
# License:  GPLv2
# Web:      https://github.com/VojtechMyslivec/letsencrypt-zimbra
#
# --------------------------------------------------------------------
set -o nounset

SCRIPTNAME=${0##*/}
USAGE="USAGE
    $SCRIPTNAME -h
    $SCRIPTNAME [-q] [-t]

DESCRIPTION
    This script is used for extend the already-deployed zimbra
    (so-called) commercial certificate issued by Let's Encrypt
    certification authority.

    It reads its configuration file letsencrypt-zimbra.cfg which
    must be located in the same directory as this script.

    The script will stop zimbra' services for a while and restart
    them once the certificate is extended and deployed. If the
    obtained certificate isn't valid after all, Zimbra will start
    with the old certificate unchanged.

    Friendly notice: restarting Zimbra take a while (1 m+).

    Depends on:
        zimbra
        letsencrypt-auto (certbot) utility
        openssl

OPTIONS
    -h      Prints this message and exits

    -q      Quiet mode, suitable for cron
    -t      Use staging Let's Encrypt URL; will issue not-trusted
            certificate, but useful for testing"

# --------------------------------------------------------------------
# -- Functions -------------------------------------------------------
# --------------------------------------------------------------------
# common message format, called by error, warning, information, ...
#  $1 - level
#  $2 - message
message() {
    echo "$SCRIPTNAME: $1: $2" >&2
}

error() {
    message "error" "$*"
}

warning() {
    message "warning" "$*"
}

information() {
    message "info" "$*"
}

# is $1 a readable ordinary file?
readable_file() {
    [ -f "$1" -a -r "$1" ]
}

# is $1 a executable ordinary file?
executable_file() {
    [ -f "$1" -a -x "$1" ]
}

cleanup() {
    [ -d "$temp_dir" ] && {
        rm -r "$temp_dir" || {
            warning "Cannot remove temporary directory '$temp_dir'. You should check it for private data."
        }
    }
}

# just a kindly message how to fix stopped nginx
fix_nginx_message() {
    cat >&2 <<EOF
        You must probably fix it with:
          \`zmproxyctl start; zmmailboxdctl start\`
        command or something.
EOF
}

# this function will stop Zimbra's nginx
stop_nginx() {
    zmproxyctl stop > /dev/null && \
      zmmailboxdctl stop > /dev/null || {
        error "There were some error during stopping the Zimbra' nginx."
        fix_nginx_message
        cleanup
        exit 3
    }
}

# and another one to start it
start_nginx() {
    zmproxyctl start > /dev/null && \
      zmmailboxdctl start > /dev/null || {
        error "There were some error during starting the Zimbra' nginx."
        fix_nginx_message
        cleanup
        exit 3
    }
}

# this function will constructs openssl csr config to stdout
# arguments are used as SAN
assemble_csr_config() {
    local i=1
    typeset -i i

    echo "$openssl_config"

    for arg; do
        echo "DNS.${i} = ${arg}"
        i+=1
    done
}

# --------------------------------------------------------------------
# -- Variables -------------------------------------------------------
# --------------------------------------------------------------------
letsencrypt_zimbra_dir="${0%/*}"
letsencrypt_zimbra_config="${letsencrypt_zimbra_dir}/letsencrypt-zimbra.cfg"
source "$letsencrypt_zimbra_config" || {
    error "Can not source config file '$letsencrypt_zimbra_config'"
    exit 1
}

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

[alt_names]"


# the name of file which letsencrypt will generate
letsencrypt_issued_cert_file="0000_cert.pem"
# intermediate CA
letsencrypt_issued_intermediate_CA_file="0000_chain.pem"

certbot_extra_args=()
TESTING='false'

# --------------------------------------------------------------------
# -- Usage -----------------------------------------------------------
# --------------------------------------------------------------------
while getopts ':hqt' OPT; do
    case "$OPT" in
        h)
            echo "$USAGE"
            exit 0
            ;;

        q)
            certbot_extra_args+=("--quiet")
            ;;

        t)
            certbot_extra_args+=("--staging")
            TESTING='true'
            ;;

        \?)
            error "Illegal option '-$OPTARG'"
            exit 1
            ;;
    esac
done
shift $(( OPTIND-1 ))

# extra args?
[ $# -eq 0 ] || {
    echo "$USAGE" >&2
    exit 1
}

# root CA certificate - zimbra needs it
if [ "$TESTING" == 'false' ]; then
    root_CA_file="${letsencrypt_zimbra_dir}/DSTRootCAX3.pem"
else
    root_CA_file="${letsencrypt_zimbra_dir}/fakelerootx1.pem"
fi


# --------------------------------------------------------------------
# -- Tests -----------------------------------------------------------
# --------------------------------------------------------------------

# check simple email format
[[ "$email" =~ ^[^[:space:]]+@[^[:space:]]+\.[^[:space:]]+$ ]] || {
    error "email '$email' is in wrong format - use user@domain.tld"
    exit 2
}

# check that common_names is an array
declare -p common_names 2> /dev/null \
  | grep -q '^declare -a ' || {
    error "parameter common_names must be an array"
    exit 2
}
# check that common_names have at least 1 item
[ ${#common_names[@]} -gt 0 ] || {
    error "array common_names must have at least 1 item"
    exit 2
}

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

# create the openssl config file from common_names array
assemble_csr_config "${common_names[@]}" > "$openssl_config_file"

# --------------------------------------------------------------------
# -- Obtaining the certificate ---------------------------------------
# --------------------------------------------------------------------

# create the certificate signing request [csr]
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
# letsencrypt utility stores the obtained certificates in PWD
# so we must cd in the temp directory
cd "$temp_dir"

sudo "$letsencrypt" certonly \
  --standalone \
  --non-interactive --agree-tos \
  "${certbot_extra_args[@]}" \
  --email "$email" --csr "$request_file" || {
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

touch "$chain_file" || {
    error "Cannot create a chain file '$chain_file'."
    cleanup
    exit 4
}

# change ownership to zimbra user
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
cat "$intermediate_CA_file" "$root_CA_file" > "$chain_file"

# verify it with Zimbra tool
"$zmcertmgr" verifycrt comm "$zimbra_key" "$cert_file" "$chain_file" > /dev/null || {
    error "Verification of the issued certificate with '$zmcertmgr' failed."
    cleanup
    exit 4
}

# install the certificate to Zimbra
"$zmcertmgr" deploycrt comm "$cert_file" "$chain_file" > /dev/null || {
    error "Installation of the issued certificate with '$zmcertmgr' failed."
    cleanup
    exit 4
}


# finally, restart the Zimbra
"$zmcontrol" restart > /dev/null || {
    error "Restarting zimbra failed."
    cleanup
    exit 5
}


# --------------------------------------------------------------------
# -- Cleanup ---------------------------------------------------------
# --------------------------------------------------------------------

cleanup
