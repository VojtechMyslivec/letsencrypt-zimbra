#!/bin/bash
# author: Vojtech Myslivec <vojtech@xmyslivec.cz>
# GPLv2 licence

SCRIPTNAME=${0##*/}

USAGE="USAGE
    $SCRIPTNAME -h | --help | help
    $SCRIPTNAME

    This script is used for extend the already-deployed gitlab
    nginx certificate issued by Let's Encrypt certification
    authority.

    The script will stop gitlab' services for a while and restart
    them once the certificate is extended and deployed. If the
    obtained certificate isn't valid after all, gitlab will start
    with the old certificate unchanged.

    Suitable to be run via cron.

    Depends on:
        gitlab
        letsencrypt-auto utility
        openssl"

# --------------------------------------------------------------------
# -- Variables -------------------------------------------------------
# --------------------------------------------------------------------
# should be in config file o_O

# letsencrypt tool
letsencrypt="/opt/letsencrypt/letsencrypt-auto"
# the name of file which letsencrypt will generate
letsencrypt_issued_cert_file="0000_cert.pem"
# intermediate CA
letsencrypt_issued_intermediate_CA_file="0000_chain.pem"
# root CA
root_CA_file="/opt/letsencrypt-gitlab/DSTRootCAX3.pem"

# gitlab controller
gitlab_ctl="gitlab-ctl"
# gitlab' services controller -- to start/stop nginx
gitlab_sv_ctl="/opt/gitlab/embedded/bin/sv"

# this is the server certificate with CA together -- alias chain
ssl_dir="/etc/ssl/private"
gitlab_cert="${ssl_dir}/chain_rsa_vyvoj.meteocentrum.cz.pem"
gitlab_key="${ssl_dir}/key_rsa_vyvoj.meteocentrum.cz.pem"

# common name in the certificate
CN="vyvoj.meteocentrum.cz"
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
        '${gitlab_ctl} restart' or '${gitlab_ctl} reconfigure'
        commands or something." >&2
}

# this function will stop gitlab's nginx
stop_nginx() {
    "$gitlab_sv_ctl" stop nginx > /dev/null || {
        error "There were some error during stopping the gitlab' nginx."
        fix_nginx_message
        cleanup
        exit 3
    }
}

# and another one to start it
start_nginx() {
    "$gitlab_sv_ctl" start nginx > /dev/null || {
        error "There were some error during starting the gitlab' nginx."
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

readable_file "$gitlab_key" || {
    error "Private key '$gitlab_key' isn't readable file."
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
    -key "$gitlab_key" \
    -out "$request_file" || {
    error "Cannot create the certificate signing request."
    cleanup
    exit 3
}

# release the 443 port -- stop gitlab' nginx
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

# start gitlab' nginx again
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

# # create one CA chain file
# cat "$root_CA_file" "$intermediate_CA_file" > "$chain_file"
# create one cert with  chain file
cat "$cert_file" "$intermediate_CA_file" > "$chain_file"


# install the certificate to gitlab -- simply copy the file on the place
# keep one last certificate in ssl_dir
mv "$gitlab_cert" "$gitlab_cert-bak" || {
    error "Cannot backup (move) the old certificate '$gitlab_cert'."
    cleanup
    exit 4
}
# replace it with the new issued certificate
mv "$chain_file" "$gitlab_cert" || {
    error "Installation of the issued certificate with '$zmcertmgr' failed."
    cleanup
    exit 4
}


# finally, restart the gitlab
"$gitlab_ctl" restart > /dev/null || {
    error "Restarting gitlab services failed."
    cleanup
    exit 5
}


# --------------------------------------------------------------------
# -- Cleanup ---------------------------------------------------------
# --------------------------------------------------------------------

cleanup

