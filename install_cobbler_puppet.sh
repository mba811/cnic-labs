#!/bin/bash 
set -x
#--------------------------------- Cobbler -------------------------------------

# 一些基本的变量
TOP_DIR=$(cd $(dirname "$0") && pwd)
COBBLER_WEB_PORT=12002
IFACE=eth0
ROOT_PASSWD="eccp"
IPADDR=$(ifconfig $IFACE | awk '/inet addr/ {print $2}' | awk -F: '{print $2}')
GATEWAY=$(route -n | grep ^0.0.0.0 | awk '{print $2}')
CHECK_HOSTNAME=$(hostname | awk -F. '{print $3}')
ZONENAME=$(hostname | awk -F . '{print $2"."$3}')
LS_ISO=$(file /opt/*.iso | grep 'Ubuntu-Server 1[2,3]' | head -n1)
ISO_NAME=$(echo $LS_ISO | awk -F: '{print $1}')
ISO_TYPE=$(echo $LS_ISO | awk -F"'" '{print $2}' | awk '{print $1"-"$2}')

### Puppet 需要的变量
COBBLER_PRESEED="/var/lib/cobbler/kickstarts/eccp.preseed"
AGENT_UP_TIME="5"    # Second

## 判断 IP 地址是否设置; 主机名是否为 FQDN; /opt/下是否存在 ISO 文件; 是否有网关.
if [ "$IPADDR" = "" -o "$ZONENAME" = "." -o "$LS_ISO" = "" -o "$GATEWAY" = "" -o "$CHECK_HOSTNAME" = "" ]
then
    echo "\nERROR: 'Not set ip address!' or 'Hostname not FQDN!' or 'Iso not found!' or 'Not set gateway!'\n"
    exit 0
fi

## 判断 GATEWAY 是否和 IP 地址相同
if [ "$GATEWAY" = "$IPADDR" ]
then
    echo "\nERROR: 'IP Gateway can not be qeual!'\n"
    exit 0
fi

## DNS 没有指向自己的 IP, 退出脚本
cat /etc/network/interfaces | grep dns-nameservers | grep $IPADDR 
if [ "$?" -ne "0" ]
then
    echo "\nERROR: 'In /etc/network/interfaces does not have its own configuration dns ip equal!'\n"
    exit 0
fi

## deb 本地源、Pypi 本地源
[ ! -e /var/www/ ] && echo "Copy file ing......" && mkdir /var/www/
cp -r $TOP_DIR/pip-packages /var/www/ && cp -r $TOP_DIR/deb-packages /var/www/
cp $TOP_DIR/puppet/files/nova-sshkey/* /var/www/
echo "deb file:///var/www/ deb-packages/" > /etc/apt/sources.list
apt-get update || exit 0

## 安装相关软件包
apt-get -y --force-yes install cobbler cobbler-web dnsmasq debmirror ntp unzip ipmitool || exit 0

## 修改 Cobbler 配置文件
COBBLER_PATH='/etc/cobbler/settings'
sed -i '/^manage_dhcp:.*$/ s/0/1/g' $COBBLER_PATH
sed -i '/^manage_dns:.*$/ s/0/1/g' $COBBLER_PATH
sed -i '/^manage_rsync:.*$/ s/0/1/g' $COBBLER_PATH
sed -i "s/^next_server:.*$/next_server: $IPADDR/g" $COBBLER_PATH
sed -i "s/^server:.*$/server: $IPADDR/g" $COBBLER_PATH
sed -i 's/= manage_bind/= manage_dnsmasq/g' /etc/cobbler/modules.conf
sed -i 's/= manage_isc/= manage_dnsmasq/g' /etc/cobbler/modules.conf
grep $COBBLER_WEB_PORT /etc/apache2/ports.conf || sed -i "s/Listen 80/Listen 80\nListen $COBBLER_WEB_PORT/g" /etc/apache2/ports.conf
grep $COBBLER_WEB_PORT $COBBLER_PATH || sed -i "/http_port: .*$/ s/80/$COBBLER_WEB_PORT/g" $COBBLER_PATH
/etc/init.d/apache2 restart
cp $TOP_DIR/eccp.preseed $COBBLER_PRESEED
sed -i "s/changeme/$ROOT_PASSWD/g" $COBBLER_PRESEED
sed -i "s/hostname string.*$/hostname string $IPADDR/g" $COBBLER_PRESEED
sed -i "s/directory string.*$/directory string \/cobbler\/ks_mirror\/ECCP-$ISO_TYPE/g" $COBBLER_PRESEED
sed -i "s/security_host string.*$/security_host string $IPADDR/g" $COBBLER_PRESEED
sed -i "s/security_path string.*$/security_path string \/cobbler\/ks_mirror\/ECCP-$ISO_TYPE/g" $COBBLER_PRESEED

echo "server $IPADDR
server 127.127.1.0
fudge 127.127.1.0 stratum 10" >> /etc/ntp.conf
cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
/etc/init.d/ntp restart

## DNSmasq 模版设置
cat > /etc/cobbler/dnsmasq.template << _GEEK_
# Cobbler generated configuration file for dnsmasq
# \$date 
#

# resolve.conf .. ?
#no-poll
#enable-dbus
read-ethers
addn-hosts = /etc/puppet/modules/bases/templates/hosts.erb
domain=$(hostname | awk -F. '{print $2"."$3}')
interface=$IFACE
dhcp-range=$(echo $IPADDR | awk -F. '{print $1"."$2"."$3}').0,static
dhcp-option=3,$IPADDR
dhcp-lease-max=1000
dhcp-authoritative
dhcp-boot=pxelinux.0
dhcp-boot=net:normalarch,pxelinux.0
dhcp-boot=net:ia64,\$elilo

\$insert_cobbler_system_definitions
_GEEK_
[ ! -e /etc/dnsmasq.d/hosts.conf ] && touch /etc/dnsmasq.d/hosts.conf

## 挂在 ISO 镜像，并导入
umount $ISO_NAME
[ ! -e /geek ] && mkdir /geek
mount -o loop $ISO_NAME /geek/ || exit 0
cobbler import --path=/geek --name=ECCP-$ISO_TYPE
cobbler distro edit --name=ECCP-$ISO_TYPE-x86_64 \
--kernel=/var/www/cobbler/ks_mirror/ECCP-$ISO_TYPE/install/netboot/ubuntu-installer/amd64/linux \
--initrd=/var/www/cobbler/ks_mirror/ECCP-$ISO_TYPE/install/netboot/ubuntu-installer/amd64/initrd.gz \
--os-version=precise
cobbler profile edit --name=ECCP-$ISO_TYPE-x86_64 \
--kopts="netcfg/choose_interface=auto " \
--kickstart=$COBBLER_PRESEED

## 设置 cobbler_web 登录用户名字:cobbler 密码:cobbler
echo "cobbler:Cobbler:a2d6bae81669d707b72c0bd9806e01f3" > /etc/cobbler/users.digest

/etc/init.d/cobbler restart
sleep 5
cobbler sync || sleep 5 && cobbler sync


#--------------------------------- Puppet -------------------------------------

echo "$IPADDR $(hostname)" >> /etc/hosts

## 配置 Puppet
apt-get -y --force-yes install puppetmaster puppet || exit 1
sed -i "s/my_ip/$IPADDR/g" $TOP_DIR/puppet/modules/all-sources/templates/pip.conf.erb
sed -i "s/my_ip/$IPADDR/g" $TOP_DIR/puppet/modules/all-sources/templates/pydistutils.cfg.erb
cp -r $TOP_DIR/puppet/* /etc/puppet/
echo "$IPADDR  $(hostname)" >> /etc/puppet/modules/bases/templates/hosts.erb

cat > /etc/puppet/autosign.conf << _GEEK_
`hostname`
*.$(hostname | awk -F. '{print $2"."$3}')
*.local
_GEEK_

/etc/init.d/puppetmaster restart
#apt-get -y remove --purge puppet
sed -i 's/-q -y/-q -y --force-yes/g' /usr/lib/ruby/1.8/puppet/provider/package/apt.rb
sed -i 's/no/yes/g' /etc/default/puppet
sed -i "s/server=.*$/server=`hostname`/g" /etc/puppet/puppet.conf
/etc/init.d/puppet restart
/etc/init.d/puppetmaster restart

# Puppet Agent--------------------------------------

cat > /var/www/post.sh << _GEEK_
#!/bin/bash

IFACE="eth0"
echo "$IPADDR  $(hostname)" >> /etc/hosts

IPADDR=\$(ifconfig \$IFACE | grep 'inet addr' | awk '{print \$2}' | awk -F: '{print \$2}')
NETMASK=\$(ifconfig \$IFACE | grep Mask | awk -F: '{print \$NF}')
echo "\$(hostname -f)" > /etc/hostname
echo "\$IPADDR  \$(hostname -f) \$(hostname)" >> /etc/hosts

cat > /etc/network/interfaces << _GEEKS_
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address \$IPADDR
    netmask \$NETMASK
    gateway $GATEWAY
    dns-nameservers 8.8.8.8 $IPADDR 
_GEEKS_
/etc/init.d/networking restart

echo "deb http://$IPADDR/ deb-packages/
#deb http://mirrors.163.com/ubuntu/ precise main universe restricted multiverse
#deb-src http://mirrors.163.com/ubuntu/ precise main universe restricted multiverse
#deb http://mirrors.163.com/ubuntu/ precise-security universe main multiverse restricted
#deb-src http://mirrors.163.com/ubuntu/ precise-security universe main multiverse restricted
#deb http://mirrors.163.com/ubuntu/ precise-updates universe main multiverse restricted
#deb http://mirrors.163.com/ubuntu/ precise-proposed universe main multiverse restricted
#deb-src http://mirrors.163.com/ubuntu/ precise-proposed universe main multiverse restricted
#deb http://mirrors.163.com/ubuntu/ precise-backports universe main multiverse restricted
#deb-src http://mirrors.163.com/ubuntu/ precise-backports universe main multiverse restricted
#deb-src http://mirrors.163.com/ubuntu/ precise-updates universe main multiverse restricted" > /etc/apt/sources.list

apt-get update
apt-get -y install ruby libshadow-ruby1.8 puppet facter --force-yes
sleep 5
apt-get -y install puppet
sed -i 's/no/yes/g' /etc/default/puppet
echo "[main]
server=$(hostname)
[agent]
runinterval=$AGENT_UP_TIME
report = true" >> /etc/puppet/puppet.conf
sed -i 's/-q -y/-q -y --force-yes/g' /usr/lib/ruby/1.8/puppet/provider/package/apt.rb
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sed -i '/ubuntu.pool.ntp.org/d' /etc/ntp.conf
sed -i "s/server ntp.ubuntu.com/server $IPADDR/g" /etc/ntp.conf
/etc/init.d/ntp stop                                                                                                                                   
ntpdate $IPADDR
/etc/init.d/ntp restart
/etc/init.d/puppet restart
echo '\$SystemLogRateLimitInterval 60' >> /etc/rsyslog.conf
echo '\$SystemLogRateLimitBurst 3000' >> /etc/rsyslog.conf

auto_mount() {
    df -h | grep /dev/\$device'1' > /dev/null && umount /dev/\$device'1'
    mkfs.xfs -i size=1024 /dev/\$device'1' -f
    mount /dev/\$device'1' /opt
    cat /etc/fstab | grep /dev/\$device'1' > /dev/null && \
    sed -i "/\$device"1"/d" /etc/fstab
    echo "/dev/\$device"1" /opt xfs noatime,nodiratime,nobarrier,logbufs=8 0 0" >> /etc/fstab
}

for device in sdb hdb
do
    # 如果设备存在
    [ -e /dev/\$device ]
    if [ "\$?" = "0" ]; then
        # 查看是否已经分区
        [ -e /dev/\$device'1' ]
        if [ "\$?" = "0" ]; then
            auto_mount
        # 没有分区
        else
            # 硬盘大于 2T
            disk=\$(fdisk -l /dev/\$device | grep "Disk /dev/\$device:" | awk -F': ' '{print \$2}' | awk -F, '{print \$1}')
            if [ "\$(echo \$disk | awk '{print \$2}')" = 'TB' ]; then
                if [ "\$(echo \$disk | awk '{print \$1}')" -gt '2' ]; then
                    parted /dev/\$device -s mklabel msdos
                    parted /dev/sdb -s mklabel gpt
                    parted /dev/\$device -s mkpart primary 0 100%
                    auto_mount
                fi
            # 硬盘小于 2T
            else
                parted /dev/\$device -s mklabel msdos
                parted /dev/\$device -s mkpart primary 0 100%
                auto_mount
            fi
        fi
    fi
done
cat > /etc/rc.local << _RC_
#!/bin/bash

tail -n 10 /var/log/syslog  | grep 'puppet Puppet configuration client --enable'
if [ "\\\$?" -eq "0" ]; then
    puppet agent --enable
    /etc/init.d/puppet restart
fi
exit 0
_RC_
cat > /var/spool/cron/crontabs/root << _CRON_
* * * * * sleep 10 && tail -n 10 /var/log/syslog | grep -v grep | egrep '(Could not retrieve catalog from remote server: SSL_CTX_use_PrivateKey:: key values mismatch|The certificate retrieved from the master does not match the|Could not send report: SSL_connect returned=1 errno=0 state=SSLv3 read server)' && su -s /bin/sh -c "exec ssh $(hostname) sudo puppet cert clean \$(hostname -f); sudo /etc/init.d/puppetmaster restart" nova && rm -fr /var/lib/puppet/ssl/* && /etc/init.d/puppet restart
_CRON_
chmod 600 /var/spool/cron/crontabs/root
chown root:crontab /var/spool/cron/crontabs/root
useradd -m nova -s /bin/bash
mkdir /home/nova/.ssh
wget http://$(hostname)/authorized_keys -P /home/nova/.ssh/
wget http://$(hostname)/id_rsa -P /home/nova/.ssh/
chmod 700 /home/nova/.ssh
chmod 600 /home/nova/.ssh/*
chown -R nova:nova /home/nova/.ssh/
echo 'nova    ALL=(ALL:ALL) NOPASSWD:NOPASSWD:ALL' >> /etc/sudoers
echo 'StrictHostKeyChecking  no' >> /etc/ssh/ssh_config
_GEEK_

chmod +x /var/www/post.sh

# Cobbler Seed--------------------------------------
cat >> $COBBLER_PRESEED << _GEEK_
d-i     preseed/late_command string true && \\
        cd /target; wget http://$IPADDR/post.sh; chmod +x ./post.sh; chroot ./ ./post.sh && \\
        true
_GEEK_

cobbler sync; /etc/init.d/cobbler restart

# ECCP Web -----------------------------------------
apt-get -y --force-yes install nginx php5-fpm php5-sqlite
cp $TOP_DIR/eccp-web/default /etc/nginx/sites-available/
chmod +x $TOP_DIR/*.py
cp -p $TOP_DIR/*.py /usr/bin/
rm -fr /usr/share/nginx/www/index.html
cp -r  $TOP_DIR/eccp-web/www/* /usr/share/nginx/www/
chmod 777 /usr/share/nginx/www/
chmod 777 /usr/share/nginx/www/data
cp $TOP_DIR/eccp-web/www.conf /etc/php5/fpm/pool.d/
/etc/init.d/php5-fpm restart
/etc/init.d/nginx restart

ps aux | grep -v grep | grep 'puppet master'
if [ "$?" -ne "0" ]; then
    /etc/init.d/puppetmaster start
fi

# www-data nginx 用户添加 sudo 权限
grep www-data /etc/sudoers || echo 'www-data    ALL=(ALL:ALL) NOPASSWD:ALL' >> /etc/sudoers
echo 3 > /proc/sys/vm/drop_caches
useradd -m nova -s /bin/bash
[ -e /home/nova/.ssh ] || mkdir /home/nova/.ssh
cp /etc/puppet/files/nova-sshkey/* /home/nova/.ssh
chmod 700 /home/nova/.ssh
chmod 600 /home/nova/.ssh/*
chown -R nova:nova /home/nova/.ssh/
grep nova /etc/sudoers || echo 'nova    ALL=(ALL:ALL) NOPASSWD:NOPASSWD:ALL' >> /etc/sudoers
