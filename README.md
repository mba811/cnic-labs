OpenStack-Source-Puppet-Install-Folsom
======================================

用 Puppet 方式来安装 OpenStack Folsom，网络使用 nova-network
addnodes.py  deb-packages  delnodes.py  eccp.preseed  init_env.sh  install_cobbler_puppet.sh  pip-packages  puppet  README.md

File:
eccp.preseed: ECCP License

Scripts:

addnodes.py: 添加节点
delnodes.py: 删除节点
init_env.sh: 初始化部署服务器基本配置
install_cobbler_puppet.sh: 用来安装部署服务器

Dir:
deb-packages: 内部 apt-get 源
pip-packages: 本地 pipy 库
puppet: puppet master 相关配置文件

注意：

在部署节点上安装 nova-control 时候会有冲突：

apt-get install lvm2
apt-get install puppet
vim /etc/puppet/puppet.conf
[main]
server=部署节点主机名

[agent]
runinterval=5
sed -i 's/-q -y/-q -y --force-yes/g' /usr/lib/ruby/1.8/puppet/provider/package/apt.rb
/etc/init.d/puppet start
装完 Horizon 时候: 
/etc/init.d/puppet stop
mv /etc/apache2/conf.d/horizon.conf /tmp
/etc/init.d/apache2 restart
开始安装计算节点,计算节点安装完以后：
mv /tmp/horizon.conf /etc/apach2/conf.d/
/etc/init.d/apache2 restart
