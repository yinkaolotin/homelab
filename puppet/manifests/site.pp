# Shared k3s cluster token.
# For homelab only. Later, move this to Hiera/secrets.
$k8s_cluster_token = 'yinkaolotin'

# Master API endpoint.
# Get this from your host with: virsh domifaddr master
$k8s_master_url = 'https://192.168.122.56:6443'

node 'master', 'master.', 'master..' {
  include homelab::base

  class { 'homelab::k8s_master':
    k8s_token => $k8s_cluster_token,
  }
}

node 'worker-1', 'worker-1.', 'worker-1..' {
  include homelab::base

  class { 'homelab::k8s_worker':
    k8s_url   => $k8s_master_url,
    k8s_token => $k8s_cluster_token,
  }
}

node 'worker-2', 'worker-2.', 'worker-2..' {
  include homelab::base

  class { 'homelab::k8s_worker':
    k8s_url   => $k8s_master_url,
    k8s_token => $k8s_cluster_token,
  }
}

# Clear error if a VM hostname/certname does not match any known node.
node default {
  fail("No matching Puppet node block for certname: ${trusted['certname']}")
}
