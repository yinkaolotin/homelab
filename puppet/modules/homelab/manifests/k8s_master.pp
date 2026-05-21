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
    command => '/bin/sh -c "for i in $(seq 1 60); do /usr/local/bin/kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes && exit 0; sleep 5; done; exit 1"',
    path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin', '/usr/local/bin'],
    require => Service['k3s'],
  }

  file { '/root/.kube':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0700',
  }

  # Copy kubeconfig to the normal root location.
  # This lets to run: sudo kubectl get nodes
  exec { 'copy-k3s-kubeconfig-for-root':
    command => '/bin/cp /etc/rancher/k3s/k3s.yaml /root/.kube/config',
    creates => '/root/.kube/config',
    path    => ['/usr/bin', '/bin'],
    require => [
      Exec['wait-for-k3s-api'],
      File['/root/.kube'],
    ],
  }  
}
