$k8s_cluster_token = 'yinkaolotin'
# virsh domifaddr master
$k8s_master_url = 'https://192.168.122.56:6443'

node 'master' {
  include homelab::base
  class { 'homelab::k8s_master':
    k8s_token => $k8s_cluster_token,
  }
}

node 'worker-1' {
  include homelab::base
  class { 'homelab::k8s_worker':
    k8s_url => $k8s_master_url
    k8s_token => $k8s_cluster_token,
  }
}

node 'worker-2' {
  include homelab::base
  class { 'homelab::k8s_worker':
    k8s_url => $k8s_master_url
    k8s_token => $k8s_cluster_token,
  }
}
