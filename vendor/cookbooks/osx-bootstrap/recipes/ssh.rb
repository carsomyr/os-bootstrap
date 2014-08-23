# -*- coding: utf-8 -*-
#
# Copyright 2014 Roy Liu
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

require "chef/shell_out"
require "pathname"

class << self
  include Chef::Mixin::ShellOut
  include OsX::Bootstrap
end

recipe = self
prefix = Pathname.new(node["osx-bootstrap"]["prefix"])
osx_bootstrap_ssh_dir = prefix + "var/osx-bootstrap/ssh"
ssh_dir = owner_dir + ".ssh"
ssh_key_file = Pathname.glob("#{osx_bootstrap_ssh_dir.to_s}/id_{rsa,dsa,ecdsa}").first

directory (owner_dir + ".ssh").to_s do
  owner recipe.owner
  group recipe.owner_group
  mode 0700
  action :create
end

template (ssh_dir + "global_known_hosts").to_s do
  source "ssh-global_known_hosts.erb"
  owner recipe.owner
  group recipe.owner_group
  mode 0600
  action :create
end

template (ssh_dir + "config").to_s do
  source "ssh-config.erb"
  owner recipe.owner
  group recipe.owner_group
  mode 0600
  action :create
end

if ssh_key_file
  installed_key_file = owner_dir + ".ssh" + ssh_key_file.basename
  installed_key_pub_file = owner_dir + ".ssh/#{ssh_key_file.basename.to_s}.pub"

  file installed_key_file.to_s do
    content ssh_key_file.open("rb") { |f| f.read }
    owner recipe.owner
    group recipe.owner_group
    mode 0600

    # Don't leak the SSH private key through a diff.
    sensitive true

    action :create
    notifies :create, "file[#{installed_key_pub_file.to_s}]", :immediately
  end

  file installed_key_pub_file.to_s do
    content(lazy { recipe.shell_out!("ssh-keygen", "-y", "-f", installed_key_file.to_s).stdout })
    owner recipe.owner
    group recipe.owner_group
    mode 0644
    action :nothing
  end
end
