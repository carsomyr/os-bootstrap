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

require "chef/provider/service/macosx"
require "etc"
require "pathname"

class ::Chef
  class Provider
    class Service
      # Workaround for querying and manipulating launchd services as their owner. Without it, `launchctl` will raise the
      # objection "Path had bad ownership/permissions" on `load` and show an incomplete list of loaded services on
      # `list`. See `https://github.com/opscode/chef/blob/11.14.6/lib/chef/provider/service/macosx.rb#L141-171` for
      # details.
      class Macosx < ::Chef::Provider::Service::Simple
        LAUNCHCTL_LIST_PATTERN = Regexp.new("\\A(0|[1-9][0-9]*|-)\t+-?(?:0|[1-9][0-9]*)\t+(.*)\\z")

        def set_service_status
          return \
            if !@plist || @service_label.empty?

          set_owner

          cmd = shell_out(
              "launchctl", "list", @service_label.to_s,
              user: @owner_uid, group: @owner_gid
          )

          @current_resource.enabled(!cmd.error?)

          if @current_resource.enabled
            shell_out!(
                "launchctl", "list",
                user: @owner_uid, group: @owner_gid
            ).stdout.chomp("\n").split("\n", -1)[1..-1].each do |line|
              m = LAUNCHCTL_LIST_PATTERN.match(line)

              raise "Invalid line #{line.dump}" \
                if !m

              @current_resource.running(m[1].to_i != 0) \
                if m[2] == @service_label.to_s
            end
          else
            @current_resource.running(false)
          end
        end

        def restart_service
          if @new_resource.restart_command
            super
          else
            stop_service
            sleep(1)

            # Reassess the service's status after stopping it.
            set_service_status

            start_service
          end
        end

        private

        # Tries to infer the service owner to shell out as:
        #
        # 1.  For plists in a user's `LaunchAgents` home directory, go by the file owner.
        # 2.  For user session-based launch agents in `/Library/LaunchAgents` and `/System/Library/LaunchAgents`, go by
        #     the username specified in the optional `parameters` attribute, then by the `SUDO_USER` environment
        #     variable (if running under `sudo`), and finally by the current user.
        # 3.  For system-wide launch daemons in `/Library/LaunchDaemons` and `/System/Library/LaunchDaemons`, go by the
        #     current user and hope that you're running as root.
        def set_owner
          plist_file = Pathname.new(@plist)
          parameters = @current_resource.parameters || {}

          if plist_file.join("../../..") == Pathname.new(Dir.home)
            stat = plist_file.stat

            @owner_uid = stat.uid
            @owner_gid = stat.gid
          elsif plist_file.dirname.basename.to_s == "LaunchAgents"
            user = Etc.getpwnam(parameters[:user] || ENV["SUDO_USER"] || Etc.getpwuid.name)

            @owner_uid = user.uid
            @owner_gid = user.gid
          else
            @owner_uid = nil
            @owner_gid = nil
          end
        end
      end
    end
  end
end
