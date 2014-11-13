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

require "openssl"
require "pathname"

module ::OsX
  module Bootstrap
    module Ssh
      ELLIPTIC_CURVE_NAMES_TO_SSH_NAMES = {
          "prime256v1" => ["ecdsa-sha2-nistp256", "nistp256"],
          "secp384r1" => ["ecdsa-sha2-nistp384", "nistp384"],
          "secp521r1" => ["ecdsa-sha2-nistp521", "nistp521"]
      }

      def self.to_public(key_data)
        key_data = key_data.open("rb") { |f| f.read } \
          if key_data.is_a?(Pathname)

        OpenSSL::PKey.read(key_data).public_key
      end

      def self.type(key_data)
        public_key = to_public(key_data)

        case public_key
          when OpenSSL::PKey::RSA
            "ssh-rsa"
          when OpenSSL::PKey::DSA
            "ssh-dss"
          when OpenSSL::PKey::EC::Point
            curve_name = public_key.group.curve_name
            ssh_names = ELLIPTIC_CURVE_NAMES_TO_SSH_NAMES[curve_name]

            raise "Unsupported elliptic curve implementation #{curve_name.dump}" \
              if !ssh_names

            ssh_names[0]
          else
            raise "Unsupported key type #{public_key.class.to_s.dump}"
        end
      end

      def self.to_public_blob(key_data)
        public_key = to_public(key_data)

        case public_key
          when OpenSSL::PKey::RSA
            [7].pack("N") + "ssh-rsa" \
              + public_key.e.to_s(0) \
              + public_key.n.to_s(0)
          when OpenSSL::PKey::DSA
            [7].pack("N") + "ssh-dss" \
              + public_key.p.to_s(0) \
              + public_key.q.to_s(0) \
              + public_key.g.to_s(0) \
              + public_key.pub_key.to_s(0)
          when OpenSSL::PKey::EC::Point
            curve_name = public_key.group.curve_name
            ssh_names = ELLIPTIC_CURVE_NAMES_TO_SSH_NAMES[curve_name]

            raise "Unsupported elliptic curve implementation #{curve_name.dump}" \
              if !ssh_names

            [19].pack("N") + ssh_names[0] \
              + [8].pack("N") + ssh_names[1] \
              + public_key.to_bn.to_s(0)
          else
            raise "Unsupported key type #{public_key.class.to_s.dump}"
        end
      end

      def self.to_public_fingerprint(key_data)
        blob = to_public_blob(key_data)
        OpenSSL::Digest::MD5.new(blob).to_s.scan(Regexp.new("[0-9a-f]{2}")).join(":")
      end
    end
  end
end
