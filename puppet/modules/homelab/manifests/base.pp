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

  service { 'qemu-guest-agent':
    ensure  => running,
    enable  => true,
    require => Package['qemu-guest-agent'],
  }
}
