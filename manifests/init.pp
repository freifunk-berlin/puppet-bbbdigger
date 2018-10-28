class bbbdigger(
  $address,
  $interface,
  $mesh_address,
  $mesh_interface,
  $tunnel_address,
  $dhcp_range,
  $name
) {
  # Network needs to be set up manually ahed of running puppet

  # Install Tunneldigger
  $install_dir = '/opt/tunneldigger'
  $max_tunnels = '250'

  class {'tunneldigger':
    install_dir         => $install_dir,
    virtualenv          => "${install_dir}/env",
    revision            => 'f68b7af4b3874601818c7e677e21461278df13f5',
    address             => $address,
    port                => '8942',
    interface           => $interface,
    max_tunnels         => $max_tunnels,
    bridge_address      => $tunnel_address,
    templates_dir       => 'bbbdigger',
    functions           => 'functions.sh',
    session_up          => 'setup_interface.sh',
    session_pre_down    => 'teardown_interface.sh',
    session_mtu_changed => 'mtu_changed.sh',
    systemd             => '1',
  }

  # Install packages need by bbbdigger
  package { [
    'dnsmasq',
    'libgps21'
  ]:
    ensure => present,
  }

  # set up dnsmasq
  $dhcp_lease_max = $max_tunnels
  file { '/etc/dnsmasq.conf':
    ensure     => file,
    content    => template('bbbdigger/dnsmasq.conf.erb'),
    notify     => Service['dnsmasq'],
  }
  file { '/etc/resolv.conf.freifunk':
    ensure     => file,
    content    => template('bbbdigger/resolv.conf.freifunk.erb'),
    require    => Package[ 'dnsmasq' ],
  }
  service { 'dnsmasq':
    ensure     => 'running',
    enable     => 'true',
    require    => Package[ 'dnsmasq' ],
  }

  # Install OLSRd with the drophna plugin
  exec {'get-olsrd.deb':
    command => "/usr/bin/wget -q https://raw.githubusercontent.com/pmelange/Temporary-Files/master/OLSRd-packages/${lsbdistid}/${lsbdistcodename}/olsrd_0.9.7.1-1_amd64.deb -O /tmp/olsrd.deb",
    creates => "/tmp/olsrd.deb",
  }
  package { 'olsrd':
    ensure     => 'present',
    provider   => 'dpkg',
    source     => '/tmp/olsrd.deb',
    require    => Exec['get-olsrd.deb'],
  }
  exec { 'get-olsrd-plugins.deb':
    command => "/usr/bin/wget -q https://raw.githubusercontent.com/pmelange/Temporary-Files/master/OLSRd-packages/${lsbdistid}/${lsbdistcodename}/olsrd-plugins_0.9.7.1-1_amd64.deb -O /tmp/olsrd-plugins.deb",
    creates => "/tmp/olsrd-plugins.deb",
  }
  package { 'olsrd-plugins':
    ensure     => 'present',
    provider   => 'dpkg',
    source     => '/tmp/olsrd-plugins.deb',
    require    => [
      Exec[ 'get-olsrd-plugins.deb' ],
      Package[ [ 'olsrd' ], [ 'libgps21' ] ],
    ],
  }
  file { '/etc/olsrd/olsrd.conf':
    ensure     => file,
    content    => template('bbbdigger/olsrd.conf.erb'),
    notify     => Service['olsrd'],
    require    => Package['olsrd'],
  }
  file { '/etc/systemd/system/olsrd.service':
    ensure     => file,
    content    => template('bbbdigger/olsrd.service.erb'),
    mode       => '755',
    require    => Package['olsrd'],
  }
  service { 'olsrd':
    ensure     => 'running',
    enable     => 'true',
    require    => [ 
      Package[ ['olsrd'], ['olsrd-plugins'] ],
      File['/etc/systemd/system/olsrd.service'],
    ],
  }
  file { '/usr/local/bin/neigh.sh':
    ensure     => file,
    content    => 'wget -q -O - http://127.0.0.1:2006/neighbours',
    mode       => '755',
    require    => Package['olsrd'],
  }
}
