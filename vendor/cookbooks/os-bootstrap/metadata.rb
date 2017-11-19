# -*- coding: utf-8 -*-
#
# Copyright 2014-2017 Roy Liu
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

name "os-bootstrap"
maintainer "Roy Liu"
maintainer_email "carsomyr@gmail.com"
license "Apache-2.0"
description "An opinionated take on the kinds of configuration you'll be doing with Chef on macOS"
long_description "An opinionated take on the kinds of configuration you'll be doing with Chef on macOS. We encourage" \
  " users to customize this cookbook for their own needs."
version "0.9.0"

supports "mac_os_x"
supports "mac_os_x_server"

depends "homebrew"
depends "plist"
depends "ruby_rbenv"
