class homelab::k8s_master (
  String $k8s_token,
){

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
token: "${k8s_token}"
write-kubeconfig-mode: "0644"
disable:
  - traefik
  - servicelb
| EOF
    require => File['/etc/rancher/k3s'],
  }

  exec { 'install-k3s-server':
    command => '/bin/sh -c "/usr/bin/curl -sfL https://get.k3s.io | /bin/sh -s - server"',
    creates => '/usr/local/bin/k3s',
    path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin', '/usr/local/bin'],
    require => File['/etc/rancher/k3s/config.yaml'],
  }

  service { 'k3s':
    ensure  => running,
    enable  => true,
    require => Exec['install-k3s-server'],
  }

  exec { 'wait-for-k3s-api':
    command => '/bin/sh -c "i=1; while [ \$i -le 60 ]; do /usr/local/bin/kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes && exit 0; i=\$((\$i+1)); sleep 5; done; exit 1"',
    path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin', '/usr/local/bin'],
    require => Service['k3s'],
  }
  
  file { '/root/.kube':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0700',
  }

  file { '/root/.kube/config':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    source  => '/etc/rancher/k3s/k3s.yaml',
    require => [
      File['/root/.kube'],
      Exec['wait-for-k3s-api'],
    ],
  }

  file { '/home/yinkaolotin/.kube':
    ensure => directory,
    owner  => 'yinkaolotin',
    group  => 'yinkaolotin',
    mode   => '0700',
  }

  file { '/home/yinkaolotin/.kube/config':
    ensure  => file,
    owner   => 'yinkaolotin',
    group   => 'yinkaolotin',
    mode    => '0600',
    source  => '/etc/rancher/k3s/k3s.yaml',
    require => [
      File['/home/yinkaolotin/.kube'],
      Exec['wait-for-k3s-api'],
    ],
  }

  exec { 'backup-k3s-kubectl-symlink':
    command => '/bin/mv /usr/local/bin/kubectl /usr/local/bin/kubectl.k3s-symlink',
    onlyif  => '/bin/sh -c "test -L /usr/local/bin/kubectl"',
    path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin', '/usr/local/bin'],
    require => Exec['install-k3s-server'],
  }

  exec { 'download-standalone-kubectl':
    command => '/usr/bin/curl -L -o /usr/local/bin/kubectl https://dl.k8s.io/release/v1.35.5/bin/linux/amd64/kubectl',
    creates => '/usr/local/bin/kubectl',
    path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin', '/usr/local/bin'],
    require => Exec['backup-k3s-kubectl-symlink'],
  }

  file { '/usr/local/bin/kubectl':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    require => Exec['download-standalone-kubectl'],
  }
}
