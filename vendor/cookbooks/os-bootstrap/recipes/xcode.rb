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

require "pathname"
require "uri"

class << self
  include Chef::Mixin::ShellOut
  include Os::Bootstrap
end

include_recipe "os-bootstrap::homebrew"

recipe = self
prefix = Pathname.new(node["os-bootstrap"]["prefix"])
homebrew_dir = prefix + "Homebrew"
xcode_url = node["os-bootstrap"]["xcode"]["url"]
volume_dir = Pathname.new(node["os-bootstrap"]["volume_root"])
caskroom_dir = prefix + "Caskroom"
xcode_archive_file = Pathname.glob("#{volume_dir.to_s}/files/[Xx]code*.{dmg,xip}").last
xcode_url ||= "file://#{URI.escape(xcode_archive_file.to_s)}" if xcode_archive_file && xcode_archive_file.file?
cask_version_pattern = Regexp.new("[Xx]code([-_].+|)\\.(?:dmg|xip)")
cask_version = (xcode_archive_file && cask_version_pattern.match(xcode_archive_file.basename.to_s)[1][1..-1]) ||
    "latest"

# The `plist_file` LWRP needs Nokogiri's XML parsing and querying capabilities.
chef_gem "install `nokogiri` for #{recipe_full_name}" do
  package_name "nokogiri"
  compile_time true
  action :install
end

require "nokogiri"

# Don't generate resources if the download URL couldn't be inferred or the cask is already installed.
if xcode_url
  ["Library/Taps/os-bootstrap",
   "Library/Taps/os-bootstrap/homebrew-xcode",
   "Library/Taps/os-bootstrap/homebrew-xcode/Casks"].each do |dir_name|
    directory (homebrew_dir + dir_name).to_s do
      owner recipe.owner
      group recipe.owner_group
      mode 0755
      action :create
    end
  end

  template (homebrew_dir + "Library/Taps/os-bootstrap/homebrew-xcode/Casks/xcode.rb").to_s do
    source "xcode-xcode.rb.erb"
    owner recipe.owner
    group recipe.owner_group
    mode 0644
    helper(:cask_version) { cask_version }
    helper(:xcode_url) { xcode_url }
    action :create
  end

  homebrew_cask "xcode" do
    notifies :run, "ruby_block[run Xcode postinstall]", :immediately
    options "--no-quarantine"
    action :update
  end

  ruby_block "run Xcode postinstall" do
    block do
      xcode_cask_dir = caskroom_dir + "xcode/#{cask_version}"
      xcode_app_dir = Pathname.glob("#{xcode_cask_dir.to_s}/Xcode*.app").first

      raise "An Xcode application bundle was not found in the cask staging directory #{xcode_app_dir.to_s.dump}" \
        if !(xcode_app_dir && xcode_app_dir.directory?)

      # Use `plutil` to read plists that are potentially in the binary format.
      xml = recipe.shell_out!("plutil", "-convert", "xml1", "-o", "-",
                              "--", (xcode_app_dir + "Contents/Info.plist").to_s).stdout
      doc = Nokogiri::XML::Document.parse(xml)
      xcode_version = doc.root.css("> dict > key[text()=\"CFBundleShortVersionString\"] + string").text
      major_version = xcode_version.split(".", -1)[0]

      case major_version
      when "11", "12", "13"
        license_version = "EA1647"
      when "9", "10"
        license_version = "EA1478"
      when "8"
        license_version = "EA1421"
      when "7"
        license_version = "EA1327"
      when "6"
        license_version = "EA1151"
      when "5"
        license_version = "EA1057"
      else
        raise "Unsupported Xcode major version #{major_version}"
      end

      # "Accept" the Xcode license by creating a magic plist file populated with the EULA and Xcode versions.
      recipe.plist_file "com.apple.dt.Xcode" do
        set "IDELastGMLicenseAgreedTo", license_version
        set "IDEXcodeVersionForAgreedToGMLicense", xcode_version
        set "IDELastBetaLicenseAgreedTo", license_version
        set "IDEXcodeVersionForAgreedToBetaLicense", xcode_version

        format :xml
        owner "root"
        group "wheel"
        mode 0644
        notifies :write, "log[Xcode license notice]", :immediately
        action :create
      end

      # Set the active developer directory to the one embedded in the newly installed Xcode. This is the equivalent of
      # `xcode-select --switch`.
      recipe.link "/var/db/xcode_select_link" do
        to (xcode_app_dir + "Contents/Developer").to_s
        owner "root"
        group "wheel"
        action :create
      end

      # Remind the user that they are automatically accepting the license.
      recipe.log "Xcode license notice" do
        message "By running this Chef recipe, you are automatically accepting the Xcode EULA version" \
          " #{license_version} for use with Xcode #{xcode_version}."
        level :info
        action :nothing
      end
    end

    action :nothing
  end
end
