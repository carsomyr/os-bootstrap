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

require "pathname"

# Provide `Shellwords` to the template resources.
require "shellwords"

class << self
  include Os::Bootstrap
  include Os::Bootstrap::Rbenv
end

include_recipe "os-bootstrap::homebrew"

recipe = self
prefix = Pathname.new(node["os-bootstrap"]["prefix"])
rbenv_root = prefix + "var/rbenv"
versions = node["os-bootstrap"]["rbenv"]["versions"]
global_version = node["os-bootstrap"]["rbenv"]["global_version"]

versions = [versions] \
  if versions.is_a?(String)

versions = versions.map do |version|
  version = ENV["RBENV_VERSION"] \
    if version == "inherit"

  version
end

global_version = ENV["RBENV_VERSION"] \
  if global_version == "inherit"

versions = versions.push(global_version).uniq \
  if global_version

monkey_patch = Module.new do
  # Override the root path discovery mechanism.
  define_method(:root_path) do
    rbenv_root.to_s
  end

  # Override this to be a no-op.
  def install_ruby_dependencies
  end
end

["rbenv_gem", "rbenv_global", "rbenv_plugin", "rbenv_rehash", "rbenv_ruby", "rbenv_script"].each do |name|
  ::Chef::ResourceResolver.new(node, name).resolve.action_class.send(:prepend, monkey_patch)
end

package "rbenv" do
  action :install
end

package "ruby-build" do
  action :install
end

directory "create `.profile.d` for #{recipe_full_name}" do
  path (recipe.owner_dir + ".profile.d").to_s
  owner recipe.owner
  group recipe.owner_group
  mode 0755
  action :create
end

# Install the Bash hook.
template (owner_dir + ".profile.d/0000_rbenv.sh").to_s do
  source "bash-0000_rbenv.sh.erb"
  owner recipe.owner
  group recipe.owner_group
  mode 0644
  helper(:rbenv_root) {prefix + "var/rbenv"}
  helper(:rbenv_bin_dir) {prefix + "opt/rbenv/bin"}
  action :create
end

directory rbenv_root.to_s do
  owner "root"
  group "admin"
  mode 0775
  action :create
end

versions.each do |version|
  ruby_block "install rbenv Ruby version #{version}" do
    block do
      recipe.as_user(recipe.owner) do
        recipe.rbenv_ruby version do
          user recipe.owner
          action :nothing
        end.run_action(:install)
      end
    end

    action :run
  end
end

if global_version
  ruby_block "set the global rbenv Ruby version #{global_version}" do
    block do
      recipe.as_user(recipe.owner) do
        recipe.rbenv_global global_version do
          user recipe.owner
          root_path rbenv_root.to_s
          action :nothing
        end.run_action(:create)
      end
    end

    action :run
  end
end
