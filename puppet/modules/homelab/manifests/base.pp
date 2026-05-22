class homelab::base {
  package { [
    'curl',
    'vim',
    'git',
    'htop',
    'net-tools',
    'qemu-guest-agent',
    'ca-certificates',
  ]:
    ensure => installed,
  }

  file { '/home/yinkaolotin/.puppet/etc':
    ensure => directory,
    owner  => 'yinkaolotin',
    group  => 'yinkaolotin',
    mode   => '0755',
  }

  file { '/home/yinkaolotin/.puppet/etc/puppet.conf':
    ensure  => file,
    owner   => 'yinkaolotin',
    group   => 'yinkaolotin',
    mode    => '0644',
    require => File['/home/yinkaolotin/.puppet/etc'],
  }

  ini_setting { 'set-puppet-certname':
    ensure  => present,
    path    => '/home/yinkaolotin/.puppet/etc/puppet.conf',
    section => 'main',
    setting => 'certname',
    value   => $facts['networking']['hostname'],
    require => File['/home/yinkaolotin/.puppet/etc/puppet.conf'],
  }

  service { 'qemu-guest-agent':
    ensure  => running,
    enable  => true,
    require => Package['qemu-guest-agent'],
  }
}
