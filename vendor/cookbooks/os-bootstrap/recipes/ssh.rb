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

require "base64"
require "pathname"
require "socket"

class << self
  include Chef::Mixin::ShellOut
  include Os::Bootstrap
end

include_recipe "os-bootstrap::homebrew"

recipe = self
prefix = Pathname.new(node["os-bootstrap"]["prefix"])
os_bootstrap_ssh_dir = prefix + "var/user_data/ssh"
ssh_dir = owner_dir + ".ssh"
ssh_key_file = Pathname.glob("#{os_bootstrap_ssh_dir.to_s}/id_{rsa,dsa,ecdsa}").first

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

directory "create `.profile.d` for #{recipe_full_name}" do
  path (recipe.owner_dir + ".profile.d").to_s
  owner recipe.owner
  group recipe.owner_group
  mode 0755
  action :create
end

# Install the Bash hook.
template (owner_dir + ".profile.d/0003_ssh-agent.sh").to_s do
  source "bash-0003_ssh-agent.sh.erb"
  owner recipe.owner
  group recipe.owner_group
  mode 0644
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
  end

  file installed_key_pub_file.to_s do
    lazy_content = lazy do
      key_data = installed_key_file.open("rb") { |f| f.read }
      type = Os::Bootstrap::Ssh.type(key_data)
      base64_blob = Base64.strict_encode64(Os::Bootstrap::Ssh.to_public_blob(key_data))
      comment = "#{recipe.owner}@#{Socket.gethostname.split(".", -1).first}"

      "#{type} #{base64_blob} #{comment}\n"
    end

    content lazy_content
    owner recipe.owner
    group recipe.owner_group
    mode 0644
    action :create
  end
end
