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

log_level                       :info
log_location                    STDOUT
node_name                       "workstation"
umask                           0022
chef_repo_path                  Pathname.new("../..").expand_path(__FILE__).to_s

# Just in case this hasn't already been specified on the command line with `-z`.
local_mode                      true

# Explicitly set this to prevent local mode from setting it to `~/.chef`.
config_dir                      Pathname.new("../../.chef").expand_path(__FILE__).to_s + "/"

# Don't save any attributes back to the node: Runs should be idempotent.
automatic_attribute_whitelist   []
default_attribute_whitelist     []
normal_attribute_whitelist      []
override_attribute_whitelist    []
