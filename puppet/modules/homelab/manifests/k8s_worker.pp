class homelab::k8s_worker (
  String $k8s_url,
  String $k8s_token,
) {

  file { '/etc/rancher':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { '/etc/rancher/k3s':
    ensure  => directory,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    require => File['/etc/rancher'],
  }

  file { '/etc/rancher/k3s/config.yaml':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => @("EOF"),
server: "${k8s_url}"
token: "${k8s_token}"
| EOF
    require => File['/etc/rancher/k3s'],
  }

  exec { 'install-k3s-agent':
    command => '/bin/sh -c "/usr/bin/curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC=agent /bin/sh -"',
    creates => '/usr/local/bin/k3s',
    path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin', '/usr/local/bin'],
    require => File['/etc/rancher/k3s/config.yaml'],
  }

  service { 'k3s-agent':
    ensure  => running,
    enable  => true,
    require => Exec['install-k3s-agent'],
  }
}
