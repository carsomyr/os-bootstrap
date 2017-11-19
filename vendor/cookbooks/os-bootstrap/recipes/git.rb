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

class << self
  include Os::Bootstrap
end

include_recipe "os-bootstrap::homebrew"

recipe = self

# Provide a unique description so as not to conflict with Homebrew's `package[git]` resource.
package "install `git` for #{recipe_full_name}" do
  package_name "git"
  action :install
end

template (owner_dir + ".gitconfig").to_s do
  source "git-gitconfig.erb"
  owner recipe.owner
  group recipe.owner_group
  mode 0644
  helper(:user_full_name) { recipe.user_full_name }
  helper(:user_email) { recipe.user_email }
  action :create
end
