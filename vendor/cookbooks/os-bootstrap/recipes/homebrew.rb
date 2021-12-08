# frozen_string_literal: true

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

# We need modifications to the `/etc/sudoers` file so that Homebrew installation doesn't blow up.
include_recipe "sudo"

class << self
  include Os::Bootstrap
  include Os::Bootstrap::Homebrew
end

recipe = self
script_file = owner_dir.join(".profile.d/1000_homebrew.sh")

cask_resource_class = ::Chef::ResourceResolver.new(node, "homebrew_cask").resolve.send(:prepend, Module.new do
  def initialize(name, run_context = nil)
    super(name, run_context)

    @allowed_actions.push(:update)
  end

  def can_update(arg = nil)
    set_or_return(
      :can_update,
      arg,
      kind_of: [TrueClass, FalseClass]
    )
  end
end)

cask_resource_class.action_class.send(:prepend, Module.new do
  define_method(:load_current_resource) do
    super()

    # Override the `brew` executable path, which might make the faulty assumption of `/usr/local/bin/brew`.
    new_resource.set_or_return(
      :homebrew_path,
      recipe.homebrew_executable.to_s,
      kind_of: String
    )

    # Check whether the version as specified in the cask file exists. This is in distinction to the current code, which
    # checks whether *some* version of the cask exists. Doing enables the resource `update` action in conjunction with
    # the `brew update && brew upgrade brew-cask` workflow.
    new_resource.can_update(
      shell_out(recipe.homebrew_executable.to_s, "list", "--cask", "--", new_resource.name).exitstatus != 0
    )
  end

  define_singleton_method(:prepended) do |ancestor|
    # Declare this action through the LWRP DSL to induce the automagical behavior injected by `use_inline_resources`.
    ancestor.action :update do
      if new_resource.can_update
        execute "updating cask #{new_resource.name}" do
          command [recipe.homebrew_executable.to_s, "install", "--cask", "--", new_resource.name]
          user recipe.owner
        end
      end
    end
  end
end)

tap_resource_class = ::Chef::ResourceResolver.new(node, "homebrew_tap").resolve

tap_resource_class.action_class.send(:prepend, Module.new do
  define_method(:load_current_resource) do
    super()

    # Override the `brew` executable path, which might make the faulty assumption of `/usr/local/bin/brew`.
    new_resource.set_or_return(
      :homebrew_path,
      recipe.homebrew_executable.to_s,
      kind_of: String
    )
  end
end)

# Rearrange the `PATH` environment variable so that Homebrew's directories are searched first.
ruby_block "rearrange `ENV[\"PATH\"]`" do
  block do
    env_paths = ENV["PATH"].split(":", -1).uniq
    homebrew_path = recipe.homebrew_bin_dir.to_s
    ENV["PATH"] = ([homebrew_path] + (env_paths - [homebrew_path])).join(":")
  end

  action :run
end

# Code from the original `homebrew` cookbook changed to account for Apple silicon.
if !homebrew_executable.executable?
  homebrew_go = "#{Chef::Config[:file_cache_path]}/homebrew_go"

  remote_file homebrew_go do
    source node["homebrew"]["installer"]["url"]
    checksum node["homebrew"]["installer"]["checksum"] if node["homebrew"]["installer"]["checksum"]
    mode "0755"
    retries 2
  end

  execute "install homebrew" do
    command homebrew_go
    environment lazy { {"HOME" => ::Dir.home(recipe.owner), "USER" => recipe.owner} }
    user recipe.owner
  end
end

if node["homebrew"]["auto-update"]
  execute "update homebrew from github" do
    command [recipe.homebrew_executable.to_s, "update"]
    returns [0, 1]
    environment lazy { {"HOME" => ::Dir.home(recipe.owner), "USER" => recipe.owner} }
    user recipe.owner
  end
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
  source "bash-1000_homebrew.sh.erb"
  owner recipe.owner
  group recipe.owner_group
  helper(:homebrew_bin_dir) { recipe.homebrew_bin_dir }
  mode 0o644
  action :create
end
