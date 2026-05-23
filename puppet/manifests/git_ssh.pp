class homelab::git_ssh (
  String $username = 'yinkaolotin',
  String $key_name = 'github_homelab_ed25519',
) {
  $home_dir = "/home/${username}"

  package { 'git':
    ensure => installed,
  }

  file { "${home_dir}/.ssh":
    ensure => directory,
    owner  => $username,
    group  => $username,
    mode   => '0700',
  }

  file { "${home_dir}/.ssh/config":
    ensure  => file,
    owner   => $username,
    group   => $username,
    mode    => '0600',
    content => @("EOF"),
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/${key_name}
  IdentitiesOnly yes
| EOF
    require => File["${home_dir}/.ssh"],
  }

  exec { "add-github-known-host-${username}":
    command => "/bin/sh -c 'ssh-keyscan github.com >> ${home_dir}/.ssh/known_hosts'",
    unless  => "/bin/sh -c 'test -f ${home_dir}/.ssh/known_hosts && ssh-keygen -F github.com -f ${home_dir}/.ssh/known_hosts >/dev/null'",
    path    => ['/usr/bin', '/bin'],
    require => File["${home_dir}/.ssh"],
  }

  file { "${home_dir}/.ssh/known_hosts":
    ensure  => file,
    owner   => $username,
    group   => $username,
    mode    => '0644',
    require => Exec["add-github-known-host-${username}"],
  }
}
