#!/usr/bin/env bash
# Bash script to attach to postdeploy hook for SSL
# Compatible only with Amazon Linux 2 EC2 instances

# Auto allow yes for all yum install
# Suggestion: Remove after deployment
if ! grep -q 'assumeyes=1' /etc/yum.conf; then
    echo 'assumeyes=1' | tee -a /etc/yum.conf
fi

# Increase size of string name for --domains
if which nginx; then
    http_string='^http\s*{$'
    bucket_increase='http {\nserver_names_hash_bucket_size 300;\n'
    sed -i "s/$http_string/$bucket_increase/g" /etc/nginx/nginx.conf
fi

# Install EPEL
# Source: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-linux-ami-basics.html
if ! yum list installed epel-release; then
    yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
fi

# install and compile nginx, if you need to recompile, delete the $FILE
FILE=/home/ec2-user/nginx-compiled
if ! test -f "$FILE"; then
    yum groupinstall 'Development Tools' -y
    yum install -y openssl-devel pcre-devel libxslt-devel gd gd-devel perl-ExtUtils-Embed geoip-devel gperftools-devel

    cd /home/ec2-user && wget 'http://nginx.org/download/nginx-1.16.1.tar.gz' && tar -xzvf nginx-1.16.1.tar.gz
    cd /home/ec2-user && wget 'https://github.com/openresty/headers-more-nginx-module/archive/v0.33.tar.gz' && tar -xzvf v0.33.tar.gz
    cd /home/ec2-user/nginx-1.16.1 && sudo ./configure --add-module=/home/ec2-user/headers-more-nginx-module-0.33 --prefix=/etc/nginx --prefix=/usr/share/nginx --sbin-path=/usr/sbin/nginx --modules-path=/usr/lib64/nginx/modules --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log --http-log-path=/var/log/nginx/access.log --http-client-body-temp-path=/var/lib/nginx/tmp/client_body --http-proxy-temp-path=/var/lib/nginx/tmp/proxy --http-fastcgi-temp-path=/var/lib/nginx/tmp/fastcgi --http-uwsgi-temp-path=/var/lib/nginx/tmp/uwsgi --http-scgi-temp-path=/var/lib/nginx/tmp/scgi --pid-path=/var/run/nginx.pid --lock-path=/var/lock/subsys/nginx --user=nginx --group=nginx --with-file-aio --with-ipv6 --with-http_ssl_module --with-http_v2_module --with-http_realip_module --with-http_addition_module --with-http_xslt_module=dynamic --with-http_image_filter_module=dynamic --with-http_geoip_module=dynamic --with-http_sub_module --with-http_dav_module --with-http_flv_module --with-http_mp4_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_random_index_module --with-http_secure_link_module --with-http_degradation_module --with-http_slice_module --with-http_stub_status_module --with-http_perl_module=dynamic --with-mail=dynamic --with-mail_ssl_module --with-pcre --with-pcre-jit --with-stream=dynamic --with-stream_ssl_module --with-google_perftools_module --with-debug --with-cc-opt='-O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector --param=ssp-buffer-size=4 -m64 -mtune=generic' --with-ld-opt=' -Wl,-E' && sudo make && sudo make install
    cd /home/ec2-user && sudo rm -r nginx-1.16.1* *v0.33*
    touch $FILE
    service nginx restart
fi

if ! [ -x "$(command -v certbot)" ] && yum list installed epel-release; then
    yum install certbot python2-certbot-nginx
fi

if [ ! -z "${CERTBOT_CERT_NAME+x}" ] && [[ -n "$CERTBOT_CERT_NAME" ]] && [ ! -z "${CERTBOT_EMAIL+x}" ] && [[ -n "$CERTBOT_EMAIL" ]] && [ ! -z "${CERTBOT_DOMAIN_LIST+x}" ] && [[ -n "$CERTBOT_DOMAIN_LIST" ]] && [ -x "$(command -v certbot)" ]; then
    certbot --nginx --redirect --debug --cert-name "$CERTBOT_CERT_NAME" -m "$CERTBOT_EMAIL" --domains "$CERTBOT_DOMAIN_LIST" --agree-tos --no-eff-email --keep-until-expiring --non-interactive
fi

crontab_exists() {
    crontab -l 2>/dev/null | grep 'certbot -q renew' >/dev/null 2>/dev/null
}
if ! crontab_exists ; then
    systemctl start crond
    systemctl enable crond
    line="0 */12 * * * certbot -q renew; systemctl reload nginx.service"
    (crontab -u root -l; echo "$line" ) | crontab -u root -
fi
