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
require "chef/shell_out"
require "pathname"
require "socket"

class << self
  include Chef::Mixin::ShellOut
  include OsX::Bootstrap
end

include_recipe "osx-bootstrap::homebrew"

recipe = self
prefix = Pathname.new(node["osx-bootstrap"]["prefix"])
osx_bootstrap_ssh_dir = prefix + "var/osx-bootstrap/ssh"
ssh_dir = owner_dir + ".ssh"
ssh_key_file = Pathname.glob("#{osx_bootstrap_ssh_dir.to_s}/id_{rsa,dsa,ecdsa}").first

homebrew_tap "homebrew/dupes" do
  action :tap
end

package "openssh" do
  options "--with-keychain-support"
  action :install
end

directory "create the `~/Library` directory for #{recipe_full_name}" do
  path (recipe.owner_dir + "Library").to_s
  owner recipe.owner
  group recipe.owner_group
  mode 0700
  action :create
end

directory "create the `~/Library/LaunchAgents` directory for #{recipe_full_name}" do
  path (recipe.owner_dir + "Library/LaunchAgents").to_s
  owner recipe.owner
  group recipe.owner_group
  mode 0755
  action :create
end

# Install the user agent plist.
template (owner_dir + "Library/LaunchAgents/homebrew.openssh.ssh-agent.plist").to_s do
  source "ssh-homebrew.openssh.ssh-agent.plist.erb"
  owner recipe.owner
  group recipe.owner_group
  mode 0644
  helper(:prefix) { prefix }

  # Disable OS X's pre-installed SSH agent for good measure.
  notifies :disable, "service[org.openbsd.ssh-agent]", :immediately

  notifies :restart, "service[homebrew.openssh.ssh-agent]", :immediately
  action :create
end

service "org.openbsd.ssh-agent" do
  action :nothing
end

service "homebrew.openssh.ssh-agent" do
  notifies :write, "log[\"reset the `SSH_AUTH_SOCK` environment variable\" notice]", :immediately
  action :nothing
end

# Remind the user that they need to reset the `SSH_AUTH_SOCK` environment variable for changes to take effect.
log "\"reset the `SSH_AUTH_SOCK` environment variable\" notice" do
  message "We replaced OS X's pre-installed SSH agent with the one from Homebrew's `openssh` formula. For changes to" \
    " take effect, please reset the `SSH_AUTH_SOCK` environment variable with" \
    " `SSH_AUTH_SOCK=$(launchctl getenv SSH_AUTH_SOCK)`."
  level :info
  action :nothing
end

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
  end

  file installed_key_pub_file.to_s do
    lazy_content = lazy do
      key_data = installed_key_file.open("rb") { |f| f.read }
      type = OsX::Bootstrap::Ssh.type(key_data)
      base64_blob = Base64.strict_encode64(OsX::Bootstrap::Ssh.to_public_blob(key_data))
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
