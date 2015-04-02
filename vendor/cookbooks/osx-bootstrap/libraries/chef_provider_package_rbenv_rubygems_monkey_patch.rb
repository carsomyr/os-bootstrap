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
        # Backport Chef 11 behavior into Chef 12 so that the `rbenv_gem` resource doesn't fail.
        include Chef::DSL::Recipe
      end
    end
  end
end
