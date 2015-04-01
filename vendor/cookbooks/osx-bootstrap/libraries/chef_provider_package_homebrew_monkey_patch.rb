# -*- coding: utf-8 -*-
#
# Copyright 2015 Roy Liu
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

module ::OsX
  module Bootstrap
    module HomebrewOwnerMixin
      # Normalizes the result to a username since it's a UID in Chef 12 and breaks
      # `https://github.com/opscode-cookbooks/homebrew/blob/d1b06e0/libraries/homebrew_package.rb#L102`.
      def homebrew_owner
        user = super

        user = Etc.getpwuid(user).name \
          if user.is_a?(Fixnum)

        user
      end
    end
  end
end

# Apply our monkey patch on top of the `Homebrew::Mixin` module.
::Chef::Provider::Package::Homebrew.send(:include, ::OsX::Bootstrap::HomebrewOwnerMixin)

# Set Homebrew as the default `package` resource and provider, overcoming a regression introduced in Chef 12.2.1 (see
# `https://github.com/chef/chef/commit/c793d2d`).
::Chef::Resource::HomebrewPackage.provides :package, os: "darwin"
::Chef::Provider::Package::Homebrew.provides :package, os: "darwin"
