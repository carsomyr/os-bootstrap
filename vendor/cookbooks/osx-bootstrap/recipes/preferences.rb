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
  include OsX::Bootstrap
end

# The `plist_file` LWRP needs Nokogiri's XML parsing and querying capabilities.
chef_gem "install `nokogiri` for #{recipe_full_name}" do
  package_name "nokogiri"
  compile_time true
  action :install
end

prefs = node["osx-bootstrap"]["preferences"]

plist_file "Apple Global Domain" do
  # Pressing and holding does not bring up a menu of accented keys.
  set "ApplePressAndHoldEnabled", false

  # Show all file extensions.
  set "AppleShowAllExtensions", true

  # Set fast key repeat intervals.
  set "InitialKeyRepeat", prefs["global"]["initial_key_repeat"]
  set "KeyRepeat", prefs["global"]["key_repeat"]

  # Use the function keys as standard function keys.
  #
  # Note: I'm not sure how to propagate this change back into the OS, so it's commented out for now. (Logging out and
  # restarting doesn't work.)
  # set "com.apple.keyboard.fnState", prefs["global"]["use_standard_function_keys"]

  # Set a low double click threshold.
  set "com.apple.mouse.doubleClickThreshold", prefs["global"]["double_click_threshold"]

  # Disable mouse acceleration.
  set "com.apple.mouse.scaling", -1.0

  # Disable trackpad acceleration.
  set "com.apple.trackpad.scaling", -1.0

  format :binary
  action :update
end

plist_file "com.apple.ActivityMonitor" do
  # Show all processes instead of just the user's.
  set "ShowCategory", 100

  format :binary
  action :update
end

plist_file "com.apple.Terminal" do
  profile = prefs["terminal"]["profile"]

  # We'll customize the profile's window settings below.
  set "Default Window Settings", profile

  # New windows and tabs inherit the current window's working directory, while reverting to default settings.
  set "NewWindowSettingsBehavior", prefs["terminal"]["new_windows_inherit_settings"] ? 2 : 1
  set "NewWindowWorkingDirectoryBehavior", prefs["terminal"]["new_windows_inherit_cwd"] ? 2 : 1

  # Set the font to something more readable.
  set "Window Settings", profile, "Font", Plist::Data.new(prefs["terminal"]["font"], false)

  # Don't allow the scrollback buffer to grow indefinitely, and set a generous upper limit.
  set "Window Settings", profile, "ShouldLimitScrollback", true
  set "Window Settings", profile, "ScrollbackLines", 65536

  # Make the terminal window 50% wider.
  set "Window Settings", profile, "columnCount", prefs["terminal"]["n_columns"]

  # Shells don't linger upon exit.
  set "Window Settings", profile, "shellExitAction", 1

  format :binary
  action :update
end

plist_file "com.apple.dashboard" do
  # Disable the useless Dashboard.
  set "mcx-disabled", true

  format :binary

  # We need to restart `Dock` for the changes to take effect.
  notifies :run, "execute[`killall -- Dock`]", :immediately

  action :update
end

plist_file "com.apple.dock" do
  # The Dock appears on the left-hand side.
  set "orientation", prefs["dock"]["orientation"]

  # Make the tiles bigger.
  set "tilesize", prefs["dock"]["tile_size"].to_f

  # Enable Spaces.
  set "workspaces", true

  # We need to restart `Dock` for the changes to take effect.
  notifies :run, "execute[`killall -- Dock`]", :immediately

  format :binary
  action :update
end

plist_file "com.apple.finder" do
  icon_size = prefs["finder"]["icon_size"].to_f

  # Make the icons bigger.
  set "DesktopViewSettings", "IconViewSettings", "iconSize", icon_size
  set "StandardViewSettings", "IconViewSettings", "iconSize", icon_size

  # New Finder windows show the user's home directory.
  set "NewWindowTarget", "PfHm"

  # Don't ask about changing file extensions.
  set "FXEnableExtensionChangeWarning", false

  format :binary

  # We need to restart `Finder` for the changes to take effect.
  notifies :run, "execute[`killall -- Finder`]", :immediately

  action :update
end

plist_file "com.apple.menuextra.clock" do
  # Set the clock format to something more useful.
  set "DateFormat", prefs["clock"]["format"]

  format :binary

  # We need to restart `SystemUIServer` for the changes to take effect.
  notifies :run, "execute[`killall -- SystemUIServer`]", :immediately

  action :update
end

plist_file "com.apple.screencapture" do
  # Prevent screenshots from saving with over-the-top drop shadows.
  set "disable-shadow", true

  format :binary
  action :update
end

plist_file "com.apple.symbolichotkeys" do
  # Disable the VoiceOver hotkey.
  set "AppleSymbolicHotKeys", "59", "enabled", false

  format :binary
  action :update
end

plist_file "com.apple.systempreferences" do
  # Time Machine shows network volumes other than Time Capsule.
  set "TMShowUnsupportedNetworkVolumes", true

  format :binary
  action :update
end

# Make sure to also kill `cfprefsd` along with the desired target, as it is the daemon that maintains cached version of
# plists and annoyingly writes them to disk at regular intervals. Also note that the process control is fire and forget:
# We aren't interested in the results of `killall`.

execute "`killall -- Dock`" do
  command ["killall", "--", "cfprefsd", "Dock"]
  returns [0, 1]
  action :nothing
end

execute "`killall -- Finder`" do
  command ["killall", "--", "cfprefsd", "Finder"]
  returns [0, 1]
  action :nothing
end

execute "`killall -- SystemUIServer`" do
  command ["killall", "--", "cfprefsd", "SystemUIServer"]
  returns [0, 1]
  action :nothing
end
