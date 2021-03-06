class all-sources {
    ### Base
    user { ["keystone", "glance", "cinder", "apache", "ceilometer"]:
        ensure => "present",
        shell => "/usr/sbin/nologin",
        notify => User["nova"],
    }   

    user { "nova":
        ensure => "present",
        shell => "/bin/bash",
        home => "/home/nova",
        managehome => true,
        password => "$1$n22iL1$BrZS39stYckjHET8d9xx20",
        notify => Group["kvm", "libvirtd"],
    }

    group { ["kvm", "libvirtd"]:
        ensure => "present",
    }   

    package { $source_apt_requires:
        ensure => installed,
        require => Group["kvm", "libvirtd"],
        notify => Exec["initialization base"],
    }   

    exec { "initialization base":
        command => "mkdir -p /root/.pip; usermod nova -G kvm,libvirtd; \
                    apt-get -y --force-yes install python-mysqldb mysql-client-5.5; \
                    echo 'nova    ALL=(ALL:ALL) NOPASSWD:NOPASSWD:ALL' >> /etc/sudoers; \
                    echo 'StrictHostKeyChecking  no' >> /etc/ssh/ssh_config; \
                    /etc/init.d/ssh restart; \
                    mkdir -p $source_dir/data",
        path => $command_path,
        creates => "$source_dir",
        require => Package["git"],
        notify => File["/home/nova/.ssh"],
    }   

    file { "/home/nova/.ssh":
        ensure => directory,
        owner => nova,
        group => nova,
        mode => 700,
        require => Exec["initialization base"],
        notify => File["/home/nova/.ssh/authorized_keys"],
    }
  
    file { "/home/nova/.ssh/authorized_keys":
        source => "puppet:///files/nova-sshkey/authorized_keys",
        owner => nova,
        group => nova,
        mode => 600,
        notify => File["/home/nova/.ssh/id_rsa"],
    }

    file { "/home/nova/.ssh/id_rsa":
        source => "puppet:///files/nova-sshkey/id_rsa",
        owner => nova,
        group => nova,
        mode => 600,
        notify => File["/etc/sudoers.d/nova-rootwrap"],
    }

    file { "/etc/sudoers.d/nova-rootwrap":
        source => "puppet:///files/nova-rootwrap",
        mode => "0440",
        notify => File["/etc/sudoers.d/cinder-rootwrap"],
    }   

    file { "/etc/sudoers.d/cinder-rootwrap":
        source => "puppet:///files/cinder-rootwrap",
        mode => "0440",
        notify => File["/root/.pip/pip.conf"],
    }

    file { "/root/.pip/pip.conf":
        content => template("all-sources/pip.conf.erb"),
        require => File["/etc/sudoers.d/cinder-rootwrap"],
        notify => File["/root/.pydistutils.cfg"],
    }   

    file { "/root/.pydistutils.cfg":
        content => template("all-sources/pydistutils.cfg.erb"),
        notify => File["/etc/keystone", "/var/log/keystone", "/var/lib/keystone", "/var/run/keystone"],
    }

### Keystone

    file { ["/etc/keystone", "/var/log/keystone", "/var/lib/keystone", "/var/run/keystone"]:
        ensure => directory,
        owner => "keystone",
        notify => File["$source_dir/$keystone_source_pack_name"],
    }  

    # Send tar pack
    file { "$source_dir/$keystone_source_pack_name":
        source => "puppet:///files/$keystone_source_pack_name",
        notify => Exec["untar keystone"],
    }   

    # Un pack & pip requires & install
    exec { "untar keystone":
        command => "[ -e $source_dir/keystone ] && \
                    cd $source_dir/keystone && python setup.py develop -u && \
                    rm -fr $source_dir/keystone; \
                    cd $source_dir; \
                    tar zxvf $keystone_source_pack_name; \
                    cd keystone; \
                    python setup.py egg_info; \
                    pip install -r *.egg-info/requires.txt; \
                    pip install keyring SQLAlchemy sqlalchemy-migrate; \
                    python setup.py develop; \
                    cp etc/default_catalog.templates /etc/keystone/; \
                    cp etc/policy.json /etc/keystone/; \
                    [ -e /etc/init.d/keystone ] && /etc/init.d/keystone restart; \
                    chown -R keystone:keystone /etc/keystone/ $source_dir/keystone; \
                    ps aux | grep -v grep | grep keystone-all && /etc/init.d/keystone restart; ls",
        path => $command_path,
        cwd => $source_dir,
        refreshonly => true,
        notify => File["$source_dir/$keystone_client_source_pack_name"],
    }   

    # Keystone Client
    file { "$source_dir/$keystone_client_source_pack_name":
        source => "puppet:///files/$keystone_client_source_pack_name",
        notify => Exec["untar keystone-client"],
    }   

    exec { "untar keystone-client":
        command => "[ -e $source_dir/python-keystoneclient ] && \
                    cd $source_dir/python-keystoneclient && \
                    python setup.py develop -u && rm -fr $source_dir/python-keystoneclient; \
                    cd $source_dir; \
                    tar zxvf $keystone_client_source_pack_name; \
                    cd python-keystoneclient; \
                    python setup.py egg_info; \
                    pip install -r *.egg-info/requires.txt; \
                    python setup.py develop; \
                    [ -e /etc/init.d/keystone ] && /etc/init.d/keystone restart; \
                    chown -R keystone:keystone $source_dir/python-keystoneclient; \
                    ps aux | grep -v grep | grep keystone-all && /etc/init.d/keystone restart; ls",
        path => $command_path,
        cwd => $source_dir,
        refreshonly => true,
        notify => File["/etc/glance", "$source_dir/data/glance/", "/var/run/glance", "/var/log/glance", "$source_dir/data/glance/images", "$source_dir/data/glance/image-cache/", "$source_dir/data/glance/scrubber", "/home/glance"],
    }   

## Glance
    file { ["/etc/glance", "$source_dir/data/glance/", "/var/run/glance", "/var/log/glance", "$source_dir/data/glance/images", "$source_dir/data/glance/image-cache/", "$source_dir/data/glance/scrubber", "/home/glance"]:
        ensure => directory,
        owner => "glance",
        notify => File["$source_dir/$glance_source_pack_name"],
    }  

    file { "$source_dir/$glance_source_pack_name":
        source => "puppet:///files/$glance_source_pack_name",
        notify => Exec["untar glance"],
    }

    exec { "untar glance":
        command => "[ -e $source_dir/glance ] && cd $source_dir/glance && \
                    python setup.py develop -u && rm -fr $source_dir/glance && \
                    cd $source_dir; \
                    tar zxvf $glance_source_pack_name; \
                    cd glance; \
                    python setup.py egg_info; \
                    pip install -r *.egg-info/requires.txt; \
                    python setup.py develop; \
                    cp etc/glance-api-paste.ini /etc/glance/; \
                    cp etc/schema-image.json /etc/glance/; \
                    cp etc/glance-registry-paste.ini /etc/glance/; \
                    cp etc/policy.json /etc/glance/; \
                    [ -e /etc/init.d/glance-api ] && /etc/init.d/glance-api restart; \
                    /etc/init.d/glance-registry restart; \
                    chown -R glance:glance /etc/glance/ $source_dir/glance; \
                    ps aux | grep -v grep | grep glance-api && \
                    /etc/init.d/glance-api restart && \
                    /etc/init.d/glance-registry restart; ls",
        cwd => $source_dir,
        path => $command_path,
        refreshonly => true,
        notify => File["$source_dir/$glance_client_source_pack_name"],
    }

    file { "$source_dir/$glance_client_source_pack_name":
        source => "puppet:///files/$glance_client_source_pack_name",
        notify => Exec["untar glance-client"],
    }

    exec { "untar glance-client":
        command => "[ -e $source_dir/python-glanceclient ] && cd $source_dir/python-glanceclient && \
                    python setup.py develop -u && rm -fr $source_dir/python-glanceclient && \
                    cd $source_dir; \
                    tar zxvf $glance_client_source_pack_name; \
                    cd python-glanceclient; \
                    python setup.py egg_info; \
                    pip install -r *.egg-info/requires.txt; \
                    python setup.py develop; \
                    [ -e /etc/init.d/glance-api ] && /etc/init.d/glance-api restart && \
                    /etc/init.d/glance-registry restart; \
                    chown -R glance:glance $source_dir/python-glanceclient; \
                    ps aux | grep -v grep | grep glance-api && \
                    /etc/init.d/glance-api restart && \
                    /etc/init.d/glance-registry restart; ls",
        path => $command_path,
        cwd => $source_dir,
        refreshonly => true,
        notify => File["/etc/cinder", "$source_dir/data/cinder", "/var/log/cinder/", "/var/run/cinder", "$source_dir/data/cinder/volumes"],
    }   

### Cinder
    file { ["/etc/cinder", "$source_dir/data/cinder", "/var/log/cinder/", "/var/run/cinder", "$source_dir/data/cinder/volumes"]:
        ensure => directory,
        owner => "cinder",
        notify => File["$source_dir/$cinder_source_pack_name"],
    } 

    file { "$source_dir/$cinder_source_pack_name":
        source => "puppet:///files/$cinder_source_pack_name",
        notify => Exec["untar cinder"],
    }   

    exec { "untar cinder":
        command => "[ -e $source_dir/cinder ] && cd $source_dir/cinder && \
                    python setup.py develop -u && rm -fr $source_dir/cinder; \
                    cd $source_dir; \
                    tar zxvf $cinder_source_pack_name; \
                    cd cinder; \
                    python setup.py egg_info; \
                    pip install -r *.egg-info/requires.txt; \
                    python setup.py develop; \
                    cp etc/cinder/policy.json /etc/cinder/; \
                    cp etc/cinder/rootwrap.conf /etc/cinder; \
                    cp -r etc/cinder/rootwrap.d/ /etc/cinder; \
                    [ -e /etc/init.d/cinder-api ] && /etc/init.d/cinder-api restart && \
                    /etc/init.d/cinder-scheduler restart && \
                    /etc/init.d/cinder-volume restart; \
                    chown -R cinder:cinder /etc/cinder $source_dir/cinder; \
                    ps aux | grep -v grep | grep cinder-api && \
                    /etc/init.d/cinder-api restart && \
                    /etc/init.d/cinder-volume restart && \
                    /etc/init.d/cinder-scheduler restart; ls",
        cwd => $source_dir,
        path => $command_path,
        refreshonly => true,
        notify => File["$source_dir/$cinder_client_source_pack_name"],
    }   

    file { "$source_dir/$cinder_client_source_pack_name":
        source => "puppet:///files/$cinder_client_source_pack_name",
        notify => Exec["untar cinder-client"],
    }   

    exec { "untar cinder-client":
        command => "[ -e $source_dir/python-cinderclient ] && cd $source_dir/python-cinderclient && \
                    python setup.py develop -u && rm -fr $source_dir/python-cinderclient && \ 
                    cd $source_dir; \
                    tar zxvf $cinder_client_source_pack_name; \
                    cd python-cinderclient; \
                    python setup.py egg_info; \
                    pip install -r *.egg-info/requires.txt; \
                    python setup.py develop; \
                    [ -e /etc/init.d/cinder-api ] && /etc/init.d/cinder-api restart && \
                    /etc/init.d/cinder-scheduler restart && \
                    /etc/init.d/cinder-volume restart; \
                    chown -R cinder:cinder $source_dir/python-cinderclient; \
                    ps aux | grep -v grep | grep cinder-api && \
                    /etc/init.d/cinder-api restart && \
                    /etc/init.d/cinder-volume restart && \
                    /etc/init.d/cinder-scheduler restart; ls",
        cwd => $source_dir,
        path => $command_path,
        refreshonly => true,
    }   

### Nova
    # mkdir dir
    file { ["/etc/nova", "/var/log/nova", "$source_dir/data/nova", "/var/run/nova", "$source_dir/data/nova/instances", "/var/lock/nova"]:
        ensure => directory,
        owner => "nova",
        require => Exec["untar cinder-client"],
        notify => File["$source_dir/$nova_source_pack_name"],
    }

    # nova pack
    file { "$source_dir/$nova_source_pack_name":
        source => "puppet:///files/$nova_source_pack_name",
        notify => Exec["untar nova"],
    }

    exec { "untar nova":
        command => "[ -e $source_dir/nova ] && \
                    cd $source_dir/nova && \
                    python setup.py develop -u && cd $source_dir && rm -fr $source_dir/nova && \
                    cd $source_dir; \
                    tar zxvf $nova_source_pack_name; \
                    cd nova; \
                    python setup.py egg_info; \
                    pip install -r *.egg-info/requires.txt; \
                    python setup.py develop; \
                    cp -r etc/nova/rootwrap.d /etc/nova/; \
                    cp etc/nova/policy.json /etc/nova/; \
                    chown -R nova:root /etc/nova/; \
                    [ -e /etc/init.d/nova-api ] && nova-manage db sync && /etc/init.d/nova-api restart; \
                    echo 'restart services'; \
                    [ -e /etc/init.d/nova-compute ] && /etc/init.d/nova-compute restart; \
                    echo 'restart services'; \
                    [ -e /etc/init.d/nova-network ] && /etc/init.d/nova-network restart; \
                    echo 'restart services'; \
                    [ -e /etc/init.d/nova-scheduler ] && /etc/init.d/nova-scheduler restart; \
                    echo 'restart services'; \
                    [ -e /etc/init.d/nova-novncproxy ] && /etc/init.d/nova-novncproxy restart; \
                    echo 'restart services'; \
                    [ -e /etc/init.d/nova-consoleauth ] && /etc/init.d/nova-consoleauth restart; \
                    echo 'restart services'; \
                    [ -e /etc/init.d/nova-cert ] && /etc/init.d/nova-cert restart; \
                    chown -R nova:nova /etc/nova $source_dir/nova",
        path => $command_path,
        cwd => $source_dir,
        refreshonly => true,
        notify => File["$source_dir/$nova_client_source_pack_name"],
    }

    # python-novaclient pack
    file { "$source_dir/$nova_client_source_pack_name":
        source => "puppet:///files/$nova_client_source_pack_name",
        notify => Exec["untar nova-client"],
    }

    exec { "untar nova-client":
        command => "[ -e $source_dir/python-novaclient ] && cd $source_dir/python-novaclient && \
                    python setup.py develop -u && rm -fr $source_dir/python-novaclient; \
                    cd $source_dir; \
                    tar zxvf $nova_client_source_pack_name; \
                    cd python-novaclient; \
                    python setup.py egg_info; \
                    pip install -r tools/pip-requires; \
                    python setup.py develop; \
                    [ -e /etc/init.d/nova-api ] && /etc/init.d/nova-api restart; \
                    echo 'restart services'; \
                    [ -e /etc/init.d/nova-compute ] && /etc/init.d/nova-compute restart; \
                    echo 'restart services'; \
                    [ -e /etc/init.d/nova-network ] && /etc/init.d/nova-network restart; \
                    echo 'restart services'; \
                    [ -e /etc/init.d/nova-cert ] && /etc/init.d/nova-cert restart; \
                    echo 'restart services'; \
                    [ -e /etc/init.d/nova-scheduler ] && /etc/init.d/nova-scheduler restart; \
                    echo 'restart services'; \
                    [ -e /etc/init.d/nova-novncproxy ] && /etc/init.d/nova-novncproxy restart; \
                    echo 'restart services'; \
                    [ -e /etc/init.d/nova-consoleauth ] && /etc/init.d/nova-consoleauth restart; \
                    chown -R nova:nova $source_dir/python-novaclient",
        path => $command_path,
        cwd => $source_dir,
        refreshonly => true,
        notify => File["$source_dir/$nova_novnc_source_pack_name"],
    }

    # noVNC
    file { "$source_dir/$nova_novnc_source_pack_name":
        source => "puppet:///files/$nova_novnc_source_pack_name",
        notify => Exec["untar noVNC"],
    }

    exec { "untar noVNC":
        command => "tar zxvf $nova_novnc_source_pack_name; \
                    rm -fr /usr/share/novnc; \
                    mv noVNC /usr/share/novnc; \
                    [ -e /etc/init.d/nova-novncproxy ] && /etc/init.d/nova-novncproxy restart; \
                    echo 'restart services'",
        path => $command_path,
        cwd => $source_dir,
        refreshonly => true,
        notify => File["$source_dir/websockify.tar.gz"],
    }

    # websockify pack
    file { "$source_dir/websockify.tar.gz":
        source => "puppet:///files/websockify.tar.gz",
        notify => Exec["untar websockify"],
    }

    exec { "untar websockify":
        command => "[ -e $source_dir/websockify ] && cd $source_dir/websockify && \
                    python setup.py develop -u && rm -fr $source_dir/websockify && \
                    cd $source_dir; \
                    tar zxvf websockify.tar.gz; \
                    cd websockify; \
                    python setup.py egg_info; \
                    pip install -r *.egg-info/requires.txt; \
                    python setup.py develop",
        path => $command_path,
        cwd => $source_dir,
        refreshonly => true,
    }

### Horizon

    file { "$source_dir/$horizon_source_pack_name":
        source => "puppet:///files/$horizon_source_pack_name",
        require => Exec["untar websockify"],
        notify => Exec["untar horizon"],
    }
    
    exec { "untar horizon":
        command => "[ -e $source_dir/horizon ] && cd $source_dir/horizon && \
                    python setup.py develop -u && rm -fr $source_dir/horizon; \
                    cd $source_dir; \
                    tar zxvf $horizon_source_pack_name; \
                    cd horizon; \
                    python setup.py egg_info; \
                    pip install -r *.egg-info/requires.txt; \
                    python setup.py develop; \
                    [ -e /etc/init.d/apache2 ] && /etc/init.d/apache2 restart; \
                    echo 'restart services'; \
                    [ -e /var/lib/mysql/$horizon_db_name ] && python $source_dir/horizon/manage.py syncdb --noinput; \
                    chown -R apache:apache $source_dir/horizon/",
        path => $command_path,
        cwd => $source_dir,
        refreshonly => true,
        notify => File["$source_dir/horizon/.blackhole"],
    }
    
    file { "$source_dir/horizon/.blackhole":
        ensure => directory,
        notify => File["$source_dir/openstack_auth.tar.gz"],
    }
    
    file { "$source_dir/openstack_auth.tar.gz":
        source => "puppet:///files/openstack_auth.tar.gz",
        notify => Exec["untar openstack_auth"],
    }
    
    exec { "untar openstack_auth":
        command => "[ -e $source_dir/openstack_auth ] && rm -fr $source_dir/openstack_auth;\
                    tar zxvf openstack_auth.tar.gz",
        path => $command_path,
        cwd => $source_dir,
        refreshonly => true,
        notify => File["/etc/profile.d/set_env.sh"],
    }
  
    file { "/etc/profile.d/set_env.sh":
        content => template("all-sources/set_env.sh.erb"),
        mode => 644,
        owner => 'root',
        group => 'root',
        notify => File["$source_dir/data/swift"],
    }

    file { "$source_dir/data/swift":
        ensure => directory,
        notify => File["$source_dir/python-swiftclient.tar.gz"],
    }

    file { "$source_dir/python-swiftclient.tar.gz":
        source => "puppet:///files/python-swiftclient.tar.gz",
        notify => Exec["untar swiftclient"],
    }

    exec { "untar swiftclient":
        command => "[ -e $source_dir/python-swiftclient ] && cd $source_dir/python-swiftclient && \
                    python setup.py develop -u && rm -fr $source_dir/python-swiftclient; \
                    cd $source_dir; \
                    tar zxvf python-swiftclient.tar.gz; \
                    cd python-swiftclient; \
                    python setup.py egg_info; \
                    pip install -r *.egg-info/requires.txt; \
                    pip install python-quantumclient; \
                    python setup.py develop; \
                    [ -e /etc/swift/swift.conf ] && \
                    swift-init main restart; ls",
        path => $command_path,
        cwd => $source_dir,
        refreshonly => true,
    }
}
