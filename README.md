# letsencrypt-zimbra
Files to automate the deploy of letsencrypt certificates to Zimbra

You will probably find these files usefull when you want to move your self-signed Zimbra certificate to the [letsencrypt](https://letsencrypt.org/)-signed one and automate the renewal of the certificate.

 - Start with `obtain-and-deploy-letsencrypt-cert.sh`, it is a pretty well commented shell script.
 - Feel free to inspire with the `crontab` file and *notifications*.
 - Enjoy **open-source** and **encryption**!


## Some links: 
  - https://www.zimbra.com/
  - https://letsencrypt.org/
  - https://github.com/letsencrypt/letsencrypt

## Best practices:
  - Add `--staging` parameter to `letsencrypt-auto` tool to test and/or debug `obtain-and-deploy-letsencrypt-cert.sh` script.
    - You can use prepared commented-out line in the script (presented in commit dc39984).
