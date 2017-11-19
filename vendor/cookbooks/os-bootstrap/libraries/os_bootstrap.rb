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

require "etc"
require "pathname"
require "socket"

module ::Os
  module Bootstrap
    module InstanceMethods
      RECIPE_NAME_PATTERN = Regexp.new("\\A(?:.+?)::(?:.+)\\z")

      def owner
        @owner ||= node["os-bootstrap"]["owner"] || ENV["SUDO_USER"] || Etc.getpwuid.name
      end

      def owner_group
        @owner_group ||= Etc.getgrgid(Etc.getpwnam(owner).gid).name
      end

      def owner_dir
        @owner_home ||= Pathname.new(Etc.getpwnam(owner).dir)
      end

      def user_full_name
        @user_full_name ||= node["os-bootstrap"]["user"]["full_name"] \
          || Etc.getpwnam(owner).gecos
      end

      def user_email
        @user_email ||= node["os-bootstrap"]["user"]["email"] \
          || "#{owner}@#{Socket.gethostname}"
      end

      def recipe_full_name
        "#{cookbook_name}::#{recipe_name}"
      end

      def infer_recipe_name(recipe_name)
        m = RECIPE_NAME_PATTERN.match(recipe_name)

        if !m
          "#{cookbook_name}::#{recipe_name}"
        else
          recipe_name
        end
      end
    end

    def self.included(clazz)
      clazz.send(:include, InstanceMethods)
    end
  end
end
