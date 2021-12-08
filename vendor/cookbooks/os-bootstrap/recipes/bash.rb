# frozen_string_literal: true

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

require "pathname"

# Provide `Shellwords` to the template resources.
require "shellwords"

class << self
  include Os::Bootstrap
  include Os::Bootstrap::Homebrew
end

include_recipe "os-bootstrap::homebrew"

recipe = self

package "bash" do
  action :install
end

package "bash-completion" do
  action :install
end

package "lesspipe" do
  action :install
end

template owner_dir.join(".bashrc").to_s do
  source "bash-bashrc.erb"
  owner recipe.owner
  group recipe.owner_group
  mode 0o644
  helper(:prefix) { recipe.homebrew_prefix }
  action :create
end

template owner_dir.join(".bash_profile").to_s do
  source "bash-bash_profile.erb"
  owner recipe.owner
  group recipe.owner_group
  mode 0o644
  helper(:prefix) { recipe.homebrew_prefix }
  action :create
end

# Set the user's shell to the Bash installed by Homebrew.
user owner do
  shell recipe.homebrew_bin_dir.join("bash").to_s
  action :manage
end
