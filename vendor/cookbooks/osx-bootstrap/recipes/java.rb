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
require "etc"

class << self
  include Chef::Mixin::ShellOut
  include Homebrew::Mixin
end

include_recipe "osx-bootstrap::homebrew"

recipe = self

ruby_block "refresh `sudo` timestamp" do
  block do
    homebrew_user = Etc.getpwnam(recipe.homebrew_owner).name

    if recipe.shell_out("brew", "cask", "list", "--", "java").exitstatus == 1 \
      && homebrew_user != "root" \
      && STDIN.tty?
      child_pid = fork do
        user = Etc.getpwnam(homebrew_user)

        Process.uid = user.uid
        Process.gid = user.gid

        prompt = "Installation of the `java` Homebrew cask invokes `sudo` noninteractively as unprivileged user" \
          " #{homebrew_user}. Please refresh their `sudo` timestamp to ensure success: "

        exec("sudo", "-v", "-p", prompt)
      end

      Process.waitpid(child_pid)

      raise "`sudo` timestamp refresh failed" \
        if $?.exitstatus != 0
    end

    recipe.homebrew_cask "java" do
      action :update
    end
  end

  action :run
end
