class horizon {

    package { ["apache2", "memcached", "python-memcache", "nodejs", "libapache2-mod-wsgi", "python-redis", "gettext"]:
        ensure => installed,
        notify => Exec["Add admin_token"],
    }

    exec { "Add admin_token":
        command => "echo ADMIN_TOKEN = $admin_token >> $source_dir/horizon/openstack_dashboard/settings.py; \
                    django-admin.py compilemessages -l zh_CN",
        cwd => "$source_dir/horizon/horizon",
        path => $command_path,
        unless => "grep ^ADMIN_TOKEN $source_dir/horizon/openstack_dashboard/settings.py",
        notify => File["$source_dir/horizon/openstack_dashboard/local/local_settings.py"],
    }


    file { "$source_dir/horizon/openstack_dashboard/local/local_settings.py":
        content => template("horizon/local_settings.py.erb"),
        notify => Exec["horizon syncdb"],
    }

    exec { "horizon syncdb":
        command => "python $source_dir/horizon/manage.py syncdb --noinput",
        path => $command_path,
        refreshonly => true,
        notify => File["/etc/apache2/conf.d/horizon.conf"],
    }

    file { "/etc/apache2/conf.d/horizon.conf":
        content => template("horizon/horizon.conf.erb"),
        notify => Service["apache2", "memcached"],
    }
  
    service { ["apache2", "memcached"]:
        ensure => "running",
        hasstatus => true,
        hasrestart => true,
        restart => true,
        notify => Exec["install PIL lib"],
    }

    exec { "install PIL lib":
        command => "apt-get -y --force-yes install libjpeg8 libjpeg62-dev libfreetype6 libfreetype6-dev; \
                    ln -s /usr/lib/x86_64-linux-gnu/libjpeg.so /usr/lib; \
                    ln -s /usr/lib/x86_64-linux-gnu/libfreetype.so /usr/lib; \
                    ln -s /usr/lib/x86_64-linux-gnu/libz.so /usr/lib; \
                    pip install PIL; \
                    /etc/init.d/apache2 restart",
       path => $command_path,
       creates => "/usr/lib/libz.so",
    }
}
