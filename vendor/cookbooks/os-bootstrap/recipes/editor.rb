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

require "pathname"

# Provide `Shellwords` to the template resources.
require "shellwords"

class << self
  include Os::Bootstrap
  include Os::Bootstrap::Homebrew
end

include_recipe "os-bootstrap::homebrew"

recipe = self
editor = node["os-bootstrap"]["user"]["editor"]
terminal_command_arguments = []

case editor
when "emacs"
  homebrew_tap "d12frosted/emacs-plus" do
    action :tap
  end

  package "emacs-plus" do
    action :install
  end

  template owner_dir.join(".emacs").to_s do
    source "editor-.emacs.erb"
    owner recipe.owner
    group recipe.owner_group
    mode 0o644
    action :create
  end

  # Just in case you created this first as root with `sudo -- emacs`.
  directory owner_dir.join(".emacs.d").to_s do
    owner recipe.owner
    group recipe.owner_group
    mode 0o700
    action :create
  end

  terminal_command_arguments.push("-nw")
when "vim"
  package "macvim" do
    action :install
  end

  template owner_dir.join(".vimrc").to_s do
    source "editor-.vimrc.erb"
    owner recipe.owner
    group recipe.owner_group
    mode 0o644
    action :create
  end
else
  raise "Unsupported editor #{editor.dump}"
end

directory "create `.profile.d` for #{recipe_full_name}" do
  path recipe.owner_dir.join(".profile.d").to_s
  owner recipe.owner
  group recipe.owner_group
  mode 0o755
  action :create
end

# Install the Bash hook.
template owner_dir.join(".profile.d/0002_editor.sh").to_s do
  source "bash-0002_editor.sh.erb"
  owner recipe.owner
  group recipe.owner_group
  mode 0o644
  helper(:prefix) { recipe.homebrew_prefix }
  helper(:editor) { editor }
  helper(:arguments) { terminal_command_arguments }
  action :create
end
