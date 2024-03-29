# frozen_string_literal: true

# Copyright 2014-2023 Roy Liu
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

# Include recipes specified by the user.

includes = node["os-bootstrap"]["includes"]

includes = [includes] \
  if includes.is_a?(String)

includes.each do |recipe_name|
  include_recipe infer_recipe_name(recipe_name)
end
