# -*- coding: utf-8 -*-
#
# Copyright 2017 Roy Liu
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

module ::OsX
  module Bootstrap
    module Rbenv
      # Runs the given block as a particular user and group.
      def as_user(user = nil, group = nil, &block)
        _, exit_status = Process.waitpid2(fork do
          Process.gid = Process.egid = Etc.getgrnam(group).gid \
            if group

          Process.uid = Process.euid = Etc.getpwnam(user).uid \
            if user

          block.call

          exit!(0)
        end)

        raise RuntimeError, "Child process exited with nonzero status" \
          if exit_status != 0
      end
    end
  end
end
