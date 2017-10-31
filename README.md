# letsencrypt-zimbra

Files to automate the deploy of letsencrypt certificates to Zimbra.

You will probably find these files usefull when you want to move your
self-signed Zimbra certificate to the letsencrypt-signed one and automate the
renewal of the certificate.

Start with *Setup manual* below and help message of the script
    ```
    obtain-and-deploy-letsencrypt-cert.sh -h`
    ```

Enjoy **open-source** and **encryption**!


## Requirements

- Working installation of *Zimbra Collaboration Suite*
- *certbot* utility
- *openssl* cli tool
- *sudo* privilege to run *certbot* with `zimbra` user


## Setup manual

1. Clone the repositories

    ```
    git clone https://github.com/certbot/certbot.git /opt/certbot
    git clone https://github.com/VojtechMyslivec/letsencrypt-zimbra.git /opt/letsencrypt-zimbra
    ```

2. Create and edit config file

    - Copy the example file

        ```
        cp /opt/letsencrypt-zimbra/letsencrypt-zimbra.cfg{.example,}
        ```

    - Configure your e-mail and server common names in
      `/opt/letsencrypt-zimbra/letsencrypt-zimbra.cfg`


3. Add sudo privileges to 'zimbra' user run certbot-auto

    - Copy prepared sudoers config:

        ```
        cp configs/sudoers.conf /etc/sudoers.d/zimbra_certbot
        ```

    - Test the sudo privilege for 'zimbra' user (no password needed)

        ```
        sudo -Hu zimbra sudo /opt/certbot/certbot-auto -h
        ```

4. Run the script to obtain certificate

    ```
    sudo -Hu zimbra /opt/letsencrypt-zimbra/obtain-and-deploy-letsencrypt-cert.sh -v
    ```

5. Configure cron jobs

    ```
    cp configs/cron.conf /etc/cron.d/letsencrypt-zimbra
    ```


## Test the configuration and staging environment

Let's Encrypt authority provides [rate
limits](https://letsencrypt.org/docs/rate-limits/).  The best practice is to
test the configuration and script on [staging
environment](https://letsencrypt.org/docs/staging-environment/), where rate
limits are much more benevolent. Certificates issued by this staging
environment are signed with *Fake LE ROOT* CA and so **they are not trusted**.

To use this environment, use `-t` option when running
`obtain-and-deploy-letsencrypt-cert.sh`. Also a verbose option `-v` is
recommended to see information messages what the script is doing.

When the script successfully deploy a staging cert, run the script again
with `-f` to force renew the cert with Let's Encrypt trusted CA.


## Some links

- [Zimbra](https://www.zimbra.org/)
- [Let's Encrypt](https://letsencrypt.org/)
- [certbot](https://github.com/certbot/certbot)
