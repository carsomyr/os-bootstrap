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

require "socket"

class << self
  include OsX::Bootstrap
end

# The `plist_file` LWRP needs Nokogiri's XML parsing and querying capabilities.
chef_gem "install `nokogiri` for #{recipe_full_name}" do
  package_name "nokogiri"
  compile_time true
  action :install
end

addrs = Socket.getifaddrs.map do |interface|
  interface.addr.getnameinfo[0]
end

machine_info = node["osx-bootstrap"]["machine"]["by_mac_address"].each_pair.find do |mac_addr, _|
  addrs.include?(mac_addr)
end

machine_info &&= machine_info[1]
machine_info ||= node["osx-bootstrap"]["machine"]

local_hostname = machine_info["local_hostname"]
name = machine_info["name"]

local_hostname = name.gsub(Regexp.new("[ _]"), "-").gsub(Regexp.new("[^\\-0-9A-Za-z]"), "") \
  .split("-", -1).select {|s| s != ""}.join("-") \
  if name && !local_hostname

plist_file "SystemConfiguration/preferences" do
  set "System", "Network", "HostNames", "LocalHostName", local_hostname \
    if local_hostname

  set "System", "System", "ComputerName", name \
    if name

  format :xml
  owner "root"
  group "wheel"
  mode 0644

  # We need to kill `configd` to prevent something like `hostname` from outputting stale, cached values.
  notifies :run, "execute[`killall -- configd`]", :immediately

  action :create
end

execute "`killall -- configd`" do
  command ["killall", "--", "configd"]
  returns [0, 1]
  action :nothing
end
