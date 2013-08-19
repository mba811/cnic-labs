class keystone {

    file { 
        "/etc/init.d/keystone":
            source => "puppet:///files/contrib/keystone/keystone",
            mode => "0755";

        "/etc/init/keystone.conf":
            source => "puppet:///files/contrib/keystone/keystone.conf",
            mode => "0644";
    }   

    # Conf
	file { "/etc/keystone/logging.conf":
        content => template("keystone/logging.conf.erb"),
        owner => "keystone",
        require => File["/etc/init/keystone.conf"],
        notify => Exec["keystone-db-sync"],
	}

	file { "/etc/keystone/keystone.conf":
        content => template("keystone/keystone.conf.erb"),
        owner => "keystone",
        notify => Exec["keystone-db-sync"],
	}

    exec { "keystone-db-sync":
        command => "keystone-manage db_sync; \
                    /etc/init.d/keystone restart",
        path => $command_path,
        refreshonly => true,
        notify => File["/etc/keystone/keystone.sh"],
    }

    # import Data
    file { "/etc/keystone/keystone.sh":
        content => template("keystone/keystone.sh.erb"),
        mode => 0755,
        notify => Exec["sh keystone.sh"],
    }

    exec { "sh keystone.sh":
        command => "sleep 5 && sh /etc/keystone/keystone.sh",
        path => $command_path,
        refreshonly => true,
    }
}