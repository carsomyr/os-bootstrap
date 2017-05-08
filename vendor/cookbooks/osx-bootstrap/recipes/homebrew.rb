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

class << self
  include OsX::Bootstrap
end

recipe = self
prefix = Pathname.new(node["osx-bootstrap"]["prefix"])

homebrew_cask_resource = ::Chef::ResourceResolver.new(node, "homebrew_cask").resolve.send(:prepend, Module.new do
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

::Chef::ProviderResolver.new(node, homebrew_cask_resource.new("dummy"), nil).resolve.send(:prepend, Module.new do
  define_method(:load_current_resource) do
    super()

    # Check whether the version as specified in the cask file exists. This is in distinction to the current code, which
    # checks whether *some* version of the cask exists. Doing enables the resource `update` action in conjunction with
    # the `brew update && brew upgrade brew-cask` workflow.
    new_resource.can_update(
        shell_out((prefix + "bin/brew").to_s, "cask", "list", "--", new_resource.name).exitstatus != 0
    )
  end

  define_singleton_method(:prepended) do |ancestor|
    # Declare this action through the LWRP DSL to induce the automagical behavior injected by `use_inline_resources`.
    ancestor.action :update do
      if new_resource.can_update
        execute "updating cask #{new_resource.name}" do
          command [(prefix + "bin/brew").to_s, "cask", "install", "--", new_resource.name]
          user Homebrew.owner
        end
      end
    end
  end
end)

homebrew_paths = [
    "/usr/local/bin", "/usr/local/sbin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"
]

homebrew_install_dirs = [
    "bin", "etc", "include", "lib", "lib/pkgconfig", "sbin", "share", "var", "opt",
    "var/log", "share/locale", "share/man",
    "share/man/man1", "share/man/man2", "share/man/man3", "share/man/man4",
    "share/man/man5", "share/man/man6", "share/man/man7", "share/man/man8",
    "share/info", "share/doc", "share/aclocal",
    "Caskroom", "Cellar", "Frameworks", "Homebrew", "Homebrew/Library", "Homebrew/Library/Taps"
].map {|dir_name| Pathname.new("/usr/local") + dir_name}

zsh_install_dirs = [
    "share/zsh", "share/zsh/site-functions"
].map {|dir_name| Pathname.new("/usr/local") + dir_name}

homebrew_cache_dir = owner_dir + "Library/Caches/Homebrew"
homebrew_old_cache_dir = Pathname.new("/Library/Caches/Homebrew")

# Rearrange the `PATH` environment variable so that Homebrew's directories are searched first.
ruby_block "rearrange `ENV[\"PATH\"]`" do
  block do
    env_paths = ENV["PATH"].split(":", -1).uniq
    homebrew_env_paths = homebrew_paths & env_paths
    homebrew_remaining_paths = homebrew_paths - env_paths

    path_set = Set.new(homebrew_env_paths)
    index = 0

    ENV["PATH"] = (homebrew_remaining_paths + env_paths.map do |env_path|
      if path_set.include?(env_path)
        homebrew_path = homebrew_env_paths[index]
        index += 1
        homebrew_path
      else
        env_path
      end
    end).join(":")
  end

  action :run
end

file "/etc/paths" do
  content homebrew_paths.join("\n") + "\n"
  owner "root"
  group "wheel"
  mode 0644
  action :create
end

# Create `admin` group-writable directories in advance to work around Chef's interaction with Homebrew's installation
# script. When Chef shells out (see
# `https://github.com/opscode-cookbooks/homebrew/blob/v1.7.2/recipes/default.rb#L34-37`), it does so with the original
# process' group id, which may very well be 0. This then short circuits Homebrew's permission fixing logic
# (see `https://github.com/Homebrew/homebrew/blob/8eefd4e/install#L135`) when running under `sudo`.
homebrew_install_dirs.each do |dir|
  directory dir.to_s do
    owner "root"
    group "admin"
    mode 0775
    action :create
  end
end

zsh_install_dirs.each do |dir|
  directory dir.to_s do
    owner recipe.owner
    group "admin"
    mode 0755
    action :create
  end
end

directory homebrew_cache_dir.to_s do
  owner recipe.owner
  group "admin"
  mode 0775

  # Create the old cache directory, but only once and tied to the creation of this one.
  notifies :create, "directory[#{homebrew_old_cache_dir.to_s}]", :immediately

  action :create
end

directory homebrew_old_cache_dir.to_s do
  owner recipe.owner
  group "admin"
  mode 0775
  action :nothing
end

# Install Homebrew.
include_recipe "homebrew"

# Enable `brew cask` functionality.
include_recipe "homebrew::cask"
