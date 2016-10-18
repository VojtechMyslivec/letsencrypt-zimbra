# Zimbra automated Let's Encrypt certificate generation, deployment and renewal
Files to automate the deploy of letsencrypt certificates to Zimbra

You will probably find these files useful when you want to move your self-signed Zimbra certificate to the [letsencrypt](https://letsencrypt.org/) valid one and automate the renewal of the certificate.

 - You'll need to have Certbot isntalled on your system (needs EPEL): `yum -y install certbot`
 - Clone this repo in your root folder (or wherever you want): `git clone https://github.com/penzoiders/zimbra-auto-letsencrypt.git`
 - Set your variables by editing `letsencrypt-zimbra.conf` file
 - cd to the script folder and run `./zimbra-auto-letsencrypt.sh`, sit back and relax while your server gets a fresh certificate and deploys (zimbra services will be restarted)
 - run `./zimbra-auto-letsencrypt.sh --help` for help and for a copy-paste-friendly hint to automate renewals using crontab
 - Enjoy **open-source** and **encryption**!

NOTE: Tested on Zimbra 8.7 and CentOS 7 host (will not work for Zimbra < 8.7 since zmcertmgr is running as zimbra user, on CentOS 6 you will need to install an alternate python version to run Certbot, it works but require little extra prep).

## Requirements:
  - git
  - Let's Encrypt Certbot client
  - Zimbra 8.7
  
## Tips:
  - install prerequisites on CentOS 7:
  
  `yum install git epel-release`
  
  `yum install certbot`
  
  - install CertBot on CentOS 6:
  
  setup python 2.7 repo
  
  `yum install -y https://centos6.iuscommunity.org/ius-release.rpm`
  
  `rpm --import /etc/pki/rpm-gpg/IUS-COMMUNITY-GPG-KEY`
  
  `yum -y install python27 python27-devel python27-pip python27-setuptools python27-virtualenv --enablerepo=ius`
  
  download and install Certbot and other prerequisites
  
  `yum -y install git dialog libffi-devel mod_ssl openssl-devel python-devel python-pip python-tools python-virtualenv`
  
  `wget https://dl.eff.org/certbot-auto -O /usr/bin/certbot`
  
  `chmod+x /usr/bin/certbot`
    

## References: 
  - https://wiki.zimbra.com/wiki/Installing_a_LetsEncrypt_SSL_Certificate/
  - https://github.com/letsencrypt/letsencrypt
  - https://certbot.eff.org

## Credits:
  - Vojtěch Myslivec: letsencrypt-zimbra https://github.com/VojtechMyslivec/letsencrypt-zimbra
