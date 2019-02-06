#!/bin/bash
## letsencrypt-zimbra
#
# Author:   Vojtech Myslivec <vojtech@xmyslivec.cz>
#           and others
# License:  GPLv3
# Web:      https://github.com/VojtechMyslivec/letsencrypt-zimbra
#
# --------------------------------------------------------------------
set -o nounset
set -o errexit

SCRIPTNAME=${0##*/}
USAGE="USAGE
    $SCRIPTNAME -h|-V
    $SCRIPTNAME [-q|-v] [-t] [-f|-d days]

DESCRIPTION
    This script is used to issue or renew zimbra (so-called)
    commercial certificate by Let's Encrypt certification authority.

    It reads its configuration file 'letsencrypt-zimbra.cfg' which
    must be located in the same directory as this script.

    The script will stop zimbra services for a while and restart
    them once the certificate is extended and deployed. If the
    obtained certificate isn't valid after all, Zimbra will start
    with the old certificate unchanged.

    Friendly notice: restarting Zimbra take a while.

OPTIONS
    -h      Prints this message and exits
    -V      Prints version of the script

    -d num  Do not renew the cert if it exists and will be valid
            for next 'num' days (default 30)
    -f      Force renew the certificate
    -q      Quiet mode, suitable for cron (overrides '-v')
    -v      Verbose mode, useful for testing (overrides '-q')
    -t      Use staging Let's Encrypt URL; will issue not-trusted
            certificate, but useful for testing"

# script version: major.minor(.patch)
VERSION='0.4.1'

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
    if [ "$VERBOSE" == 'true' ]; then
        message "info" "$*"
    fi
}

# is $1 a readable ordinary file?
readable_file() {
    [ -f "$1" -a -r "$1" ]
}

# is $1 a executable ordinary file?
executable_file() {
    [ -f "$1" -a -x "$1" ]
}

# is $1 a writable directory?
writable_directory() {
    [ -d "$1" -a -w "$1" ]
}

cleanup() {
    information "cleanup temp files"

    [ -d "$temp_dir" ] && {
        rm -rf "$temp_dir" || {
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
    information "stop nginx"

    zmproxyctl stop > /dev/null && \
      zmmailboxdctl stop > /dev/null || {
        error "There were some error during stopping the Zimbra' nginx."
        fix_nginx_message
        return 3
    }
}

# and another one to start it
start_nginx() {
    information "start nginx"

    zmproxyctl start > /dev/null && \
      zmmailboxdctl start > /dev/null || {
        error "There were some error during starting the Zimbra' nginx."
        fix_nginx_message
        return 3
    }
}

# Restart all zimbra services (run in subshell due to env variables)
restart_zimbra() (
    information "restart zimbra"

    # set env for perl (for zmwatch)
    if declare -v PERLLIB &> /dev/null; then
        PERLLIB="${zimbra_perllib}:${PERLLIB}"
    else
        PERLLIB="${zimbra_perllib}"
    fi
    export PERLLIB

    zmcontrol restart > /dev/null || {
        error "Restarting zimbra failed."
        return 5
    }
)

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

# a lot of binaries in zimbra bin dir
PATH="${zimbra_dir}/bin:$PATH"

perl_archname=$(perl -MConfig -e 'print $Config{archname}')
zimbra_perllib="${zimbra_dir}/common/lib/perl5/${perl_archname}:${zimbra_dir}/common/lib/perl5"


# Use default values if not set in config file
zimbra_ssl_dir="${zimbra_ssl_dir:-${zimbra_dir}/ssl/zimbra/commercial}"
zimbra_key="${zimbra_key:-${zimbra_ssl_dir}/commercial.key}"
zimbra_cert="${zimbra_cert:-${zimbra_ssl_dir}/commercial.crt}"


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

certbot_extra_args=("--non-interactive" "--agree-tos")
TESTING='false'
VERBOSE='false'
FORCE='false'
DAYS='30'

# --------------------------------------------------------------------
# -- Usage -----------------------------------------------------------
# --------------------------------------------------------------------
while getopts ':hVd:fqtv' OPT; do
    case "$OPT" in
        h)
            echo "$USAGE"
            exit 0
            ;;

        V)
            echo "letsencrypt-zimbra version $VERSION"
            exit 0
            ;;

        d)
            DAYS="$OPTARG"
            [[ "$DAYS" =~ ^[0-9]+$ ]] || {
                error "Specified number of days '$days' is not a Integer"
                exit 1
            }
            ;;

        f)
            FORCE='true'
            ;;

        q)
            certbot_extra_args+=("--quiet")
            VERBOSE='false'
            ;;

        t)
            certbot_extra_args+=("--staging")
            TESTING='true'
            ;;

        v)
            VERBOSE='true'
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
    root_CA_file="${letsencrypt_zimbra_dir}/root_certs/DSTRootCAX3.pem"
else
    root_CA_file="${letsencrypt_zimbra_dir}/root_certs/fakelerootx1.pem"
fi


# --------------------------------------------------------------------
# -- Renew? ----------------------------------------------------------
# --------------------------------------------------------------------
# check the need to renew if the cert is present an force mode is off
if ! readable_file "$zimbra_cert"; then
    information "Zimbra certificate does not exist. New cert will be deployed."
else
    if [ "$FORCE" == 'true' ]; then
        information "Running in force mode, certificate will be renewed."
    else
        if openssl x509 -checkend $(( DAYS*24*60*60 )) -in "$zimbra_cert" &> /dev/null; then
            information "Certificate will be valid for next $DAYS days, exiting (Run with '-f' to force-renew)."
            exit 0
        else
            information "Certificate will expire in $DAYS, certificate will be renewed."
        fi
    fi
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

for bin in zmcertmgr zmcontrol zmmailboxdctl zmproxyctl; do
    which "$bin" &> /dev/null || {
        error "Zimbra executable '$bin' not found"
        exit 2
    }
done

readable_file "$root_CA_file" || {
    error "The root CA certificate '$root_CA_file' isn't readable file."
    exit 2
}

writable_directory "$zimbra_ssl_dir" || {
    error "Zimbra SSL directory '$zimbra_ssl_dir' is not writable"
    exit 2
}

# Check and generate private-key if not present
if ! readable_file "$zimbra_key"; then
    information "Generating RSA private key '$zimbra_key'"
    openssl genrsa -out "$zimbra_key" 4096 &> /dev/null || {
        error "Can not generate RSA private key '$zimbra_key'"
        information "Try to generate it in Zimbra web interface or with following command:
        openssl genrsa -out '$zimbra_key' 4096"
        exit 3
    }
fi


# --------------------------------------------------------------------
# -- Temporary files -------------------------------------------------
# --------------------------------------------------------------------
temp_dir=$( mktemp -d ) || {
    error "Cannot create temporary directory."
    exit 2
}
openssl_config_file="${temp_dir}/openssl.cnf"
request_file="${temp_dir}/request.pem"

information "create csr config '$openssl_config_file'"
# create the openssl config file from common_names array
assemble_csr_config "${common_names[@]}" > "$openssl_config_file"

# --------------------------------------------------------------------
# -- Obtaining the certificate ---------------------------------------
# --------------------------------------------------------------------
information "generate csr '$request_file'"
# create the certificate signing request [csr]
openssl req -new -nodes -sha256 -outform der \
  -config "$openssl_config_file" \
  -subj '/' \
  -key "$zimbra_key" \
  -out "$request_file" || {
    error "Cannot create the certificate signing request."
    exit 3
}

# release the 443 port -- stop Zimbra' nginx
stop_nginx

# ----------------------------------------------------------
information "issue certificate; certbot_extra_args: ${certbot_extra_args[@]}"
(
    # run in subshell due to working directory and umask change

    # letsencrypt utility stores the obtained certificates in PWD
    # so we must cd in the temp directory
    cd "$temp_dir"
    # ensure generated certificate would be readable for zimbra user
    umask 0022

    sudo "$letsencrypt" certonly \
      --standalone \
      "${certbot_extra_args[@]}" \
      --email "$email" --csr "$request_file" || {
        error "The certificate cannot be obtained with '$letsencrypt' tool."
        start_nginx
        exit 4
    }

)
# ----------------------------------------------------------

# start Zimbra' nginx again
start_nginx


# --------------------------------------------------------------------
# -- Deploying the certificate ---------------------------------------
# --------------------------------------------------------------------
information "assemble cert files"
cert_file="${temp_dir}/${letsencrypt_issued_cert_file}"
intermediate_CA_file="${temp_dir}/${letsencrypt_issued_intermediate_CA_file}"
chain_file="${temp_dir}/chain.pem"

touch "$chain_file" || {
    error "Cannot create a chain file '$chain_file'."
    exit 4
}

# change ownership to zimbra user
readable_file "$cert_file" || {
    error "The issued certificate file '$cert_file' isn't readable file. Maybe it was created with different name?"
    exit 4
}

readable_file "$intermediate_CA_file" || {
    error "The issued intermediate CA file '$intermediate_CA_file' isn't readable file. Maybe it was created with different name?"
    exit 4
}

# create one CA chain file
cat "$intermediate_CA_file" "$root_CA_file" > "$chain_file"

# verify it with Zimbra tool
information "test and deploy certificates"
zmcertmgr verifycrt comm "$zimbra_key" "$cert_file" "$chain_file" > /dev/null || {
    error "Verification of the issued certificate failed."
    exit 4
}

# install the certificate to Zimbra
zmcertmgr deploycrt comm "$cert_file" "$chain_file" > /dev/null || {
    error "Installation of the issued certificate failed."
    exit 4
}


# finally, restart the Zimbra
restart_zimbra


# --------------------------------------------------------------------
# -- Cleanup ---------------------------------------------------------
# --------------------------------------------------------------------

cleanup
