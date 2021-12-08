# frozen_string_literal: true

# Copyright 2021 Roy Liu
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

module ::Os
  module Bootstrap
    module Homebrew
      def is_apple_silicon
        node["kernel"]["machine"] == "arm64"
      end

      def homebrew_prefix
        @homebrew_prefix ||= Pathname.new(
          if !is_apple_silicon
            "/usr/local"
          else
            "/opt/homebrew"
          end
        )
      end

      def homebrew_bin_dir
        @homebrew_bin_dir ||= homebrew_prefix.join("bin")
      end

      def homebrew_executable
        @homebrew_executable ||= homebrew_bin_dir.join("brew")
      end

      def homebrew_taps_dir
        @homebrew_taps_dir ||= Pathname.new(
          if !is_apple_silicon
            homebrew_prefix.join("Homebrew/Library/Taps")
          else
            homebrew_prefix.join("Library/Taps")
          end
        )
      end
    end
  end
end
