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
  # Enable or disable the menu of accented keys.
  set "ApplePressAndHoldEnabled", prefs["global"]["press_and_hold_for_character_picker"]

  # Show all file extensions or hide some common ones.
  set "AppleShowAllExtensions", prefs["global"]["show_all_file_extensions"]

  # Set fast key repeat intervals.
  set "InitialKeyRepeat", prefs["global"]["initial_key_repeat"]
  set "KeyRepeat", prefs["global"]["key_repeat"]

  # Enable or disable "Shake mouse pointer to locate" behavior.
  set "CGDisableCursorLocationMagnification", !prefs["global"]["shake_mouse_pointer_to_locate"]

  # Use the function keys as standard function keys.
  set "com.apple.keyboard.fnState", prefs["global"]["use_standard_function_keys"]

  # Set a low double click threshold.
  set "com.apple.mouse.doubleClickThreshold", prefs["global"]["double_click_threshold"]

  # Set mouse and trackpad acceleration; `nil` to disable.
  pointer_acceleration = prefs["global"]["pointer_acceleration"]

  if pointer_acceleration
    set "com.apple.mouse.scaling", pointer_acceleration
    set "com.apple.trackpad.scaling", pointer_acceleration
  else
    set "com.apple.mouse.scaling", -1.0
    set "com.apple.trackpad.scaling", -1.0
  end

  format :binary
  action :update
end

plist_file "com.apple.ActivityMonitor" do
  # Change the kind of processes displayed.
  set "ShowCategory",
      case prefs["activity_monitor"]["view_mode"]
        when "all"
          100
        when "all_hierarchical"
          101
        when "user"
          102
        when "system"
          103
        when "other"
          104
        when "active"
          105
        when "inactive"
          106
        when "windowed"
          107
        else
          raise ArgumentError, "Invalid Activity Monitor view mode"
      end

  format :binary
  action :update
end

plist_file "com.apple.Terminal" do
  profile = prefs["terminal"]["profile"]

  # We'll customize the profile's window settings below.
  set "Default Window Settings", profile

  # New windows and tabs inherit the current window's working directory, while reverting to default settings.
  set "NewWindowSettingsBehavior", prefs["terminal"]["inherit_settings_in_new_windows"] ? 2 : 1
  set "NewWindowWorkingDirectoryBehavior", prefs["terminal"]["inherit_cwd_in_new_windows"] ? 2 : 1

  # Set the font to something more readable.
  set "Window Settings", profile, "Font", Plist::Data.new(prefs["terminal"]["font"], false)

  # Set the scrollback limit. Useful for programs that log to `STDOUT`.
  scrollback_limit = prefs["terminal"]["scrollback_limit"]

  if scrollback_limit
    set "Window Settings", profile, "ShouldLimitScrollback", 1
    set "Window Settings", profile, "ScrollbackLines", scrollback_limit
  else
    set "Window Settings", profile, "ShouldLimitScrollback", 0
    set "Window Settings", profile, "ScrollbackLines", -1
  end

  # Make the terminal window 50% wider.
  set "Window Settings", profile, "columnCount", prefs["terminal"]["n_columns"]

  # Set the window action to take when the shell exits.
  set "Window Settings", profile, "shellExitAction",
      case prefs["terminal"]["window_action_on_shell_exit"]
        when "close"
          0
        when "close_if_clean_exit"
          1
        when "nothing"
          2
        else
          raise ArgumentError, "Invalid Terminal window action on shell exit"
      end

  format :binary
  action :update
end

plist_file "com.apple.dock" do
  # The Dock appears on the left-hand side.
  set "orientation", prefs["dock"]["orientation"]

  # Make the tiles bigger.
  set "tilesize", prefs["dock"]["tile_size"].to_f

  # Enable or disable Spaces.
  set "workspaces", prefs["dock"]["enable_workspaces"]

  # We need to restart `Dock` for the changes to take effect.
  notifies :run, "execute[`killall -- Dock`]", :immediately

  format :binary
  action :update
end

plist_file "com.apple.finder" do
  icon_size = prefs["finder"]["icon_size"].to_f

  # Show all files or hide some typical ones (like those beginning with `.`).
  set "AppleShowAllFiles", prefs["finder"]["show_all_files"]

  # Make the icons bigger.
  set "DesktopViewSettings", "IconViewSettings", "iconSize", icon_size
  set "StandardViewSettings", "IconViewSettings", "iconSize", icon_size

  # Set the new window view behavior.
  set "NewWindowTarget",
      case prefs["finder"]["new_window_view_mode"]
        when "computer"
          "PfCm"
        when "boot_volume"
          "PfVo"
        when "user_home"
          "PfHm"
        when "user_desktop"
          "PfDe"
        when "user_documents"
          "PfDo"
        when "user_icloud"
          "PfID"
        when "user_all_files"
          "PfAF"
        else
          raise ArgumentError, "Invalid Finder new window view mode"
      end

  # Enable or disable the warning about changing file extensions.
  set "FXEnableExtensionChangeWarning", prefs["finder"]["warn_about_file_extension_changes"]

  format :binary

  # We need to restart `Finder` for the changes to take effect.
  notifies :run, "execute[`killall -- Finder`]", :immediately

  action :update
end

plist_file "com.apple.menuextra.clock" do
  # Set the clock format to something more useful.
  content(
      "DateFormat" => prefs["clock"]["format"],
      "FlashDateSeparators" => prefs["clock"]["flash_date_separators"],
      "IsAnalog" => prefs["clock"]["is_analog"]
  )

  format :binary

  # We need to restart `SystemUIServer` for the changes to take effect.
  notifies :run, "execute[`killall -- SystemUIServer`]", :immediately

  action :create
end

plist_file "com.apple.screencapture" do
  # Enable or disable drop shadows in screenshots.
  content("disable-shadow" => !prefs["screen_capture"]["enable_drop_shadows"])

  format :binary

  # We need to restart `SystemUIServer` for the changes to take effect.
  notifies :run, "execute[`killall -- SystemUIServer`]", :immediately

  action :create
end

plist_file "com.apple.symbolichotkeys" do
  # Enable or disable the VoiceOver hotkey.
  set "AppleSymbolicHotKeys", "59", "enabled", prefs["symbolic_hotkeys"]["enable_voice_over"]

  format :binary
  action :update
end

plist_file "com.apple.systempreferences" do
  # Show or hide network volumes not recognized by Time Machine. Setting this to `true` prevents Time Machine from
  # wanting to take over said volumes.
  set "TMShowUnsupportedNetworkVolumes", prefs["system_preferences"]["show_time_machine_unsupported_volumes"]

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
