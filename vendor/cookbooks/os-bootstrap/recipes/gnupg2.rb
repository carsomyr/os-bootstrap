# frozen_string_literal: true

# Copyright 2014-2021 Roy Liu
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

class << self
  include Os::Bootstrap
  include Os::Bootstrap::Homebrew
end

include_recipe "os-bootstrap::homebrew"

recipe = self
script_file = owner_dir.join(".profile.d/0001_gnupg2.sh")

package "gnupg2" do
  action :install
end

directory "create the `~/Library` directory for #{recipe_full_name}" do
  path recipe.owner_dir.join("Library").to_s
  owner recipe.owner
  group recipe.owner_group
  mode 0o700
  action :create
end

directory "create the `~/Library/LaunchAgents` directory for #{recipe_full_name}" do
  path recipe.owner_dir.join("Library/LaunchAgents").to_s
  owner recipe.owner
  group recipe.owner_group
  mode 0o755
  action :create
end

directory "create `.profile.d` for #{recipe_full_name}" do
  path recipe.owner_dir.join(".profile.d").to_s
  owner recipe.owner
  group recipe.owner_group
  mode 0o755
  action :create
end

# Install the Bash hook.
template script_file.to_s do
  source "bash-0001_gnupg2.sh.erb"
  owner recipe.owner
  group recipe.owner_group
  mode 0o755
  helper(:prefix) { recipe.homebrew_prefix }
  action :create
end

# Install the user agent plist.
template owner_dir.join("Library/LaunchAgents/homebrew.gnupg2.gpg-agent.plist").to_s do
  source "gnupg2-homebrew.gnupg2.gpg-agent.plist.erb"
  owner recipe.owner
  group recipe.owner_group
  mode 0o644
  helper(:script_file) { script_file }
  notifies :restart, "service[homebrew.gnupg2.gpg-agent]", :immediately
  action :create
end

service "homebrew.gnupg2.gpg-agent" do
  action :nothing
end

directory owner_dir.join(".gnupg").to_s do
  owner recipe.owner
  group recipe.owner_group
  mode 0o700
  action :create
end

template owner_dir.join(".gnupg/gpg.conf").to_s do
  source "gnupg2-gpg.conf.erb"
  owner recipe.owner
  group recipe.owner_group
  mode 0o600
  action :create
end

template owner_dir.join(".gnupg/gpg-agent.conf").to_s do
  source "gnupg2-gpg-agent.conf.erb"
  owner recipe.owner
  group recipe.owner_group
  mode 0o600
  action :create
end
