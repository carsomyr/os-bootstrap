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

require "chef/dsl/recipe"

class ::Chef
  class Provider
    class Package
      class RbenvRubygems < ::Chef::Provider::Package::Rubygems
        # Fixes the chef-rbenv cookbook issues #98 and #107.
        def rehash
          e = ::Chef::Resource::RbenvRehash.new(new_resource.name, run_context)
          e.root_path rbenv_root
          e.user rbenv_user if rbenv_user
          e.action :nothing
          e.run_action(:run)
        end
      end
    end
  end
end
