#!/usr/bin/env ruby
# frozen_string_literal: true

# Copyright 2014-2022 Roy Liu
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

require "digest"
require "etc"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "rake"
require "rbconfig"
require "rexml/document"
require "shellwords"
require "yaml"

module Os
  module Bootstrap
    # A formatter for framed, line-wrapped messages.
    class Formatter
      def initialize(header, footer, line_header, line_footer = nil, line_max = nil)
        @header = header
        @footer = footer
        @line_header = line_header
        @line_footer = line_footer
        @line_max = line_max
      end

      # Formats the given string: Wraps lines to under the line size limit while applying headers and footers.
      def format(str)
        acc = ""

        acc = "#{@header}\n" \
          if @header

        single_space_pattern = Regexp.new(" ")
        line_acc = nil

        REXML::Document.new("<root>#{str}</root>").root.children.each do |node|
          case node
          when REXML::Text
            first_line = true

            node.value.split("\n", -1).each do |line|
              if !first_line
                acc += emit_line(line_acc || "")
                line_acc = nil
              end

              first_word = true

              # Apparently the string `" "` has special meaning for Ruby regular expressions, so we use a regex to
              # force the issue.
              line.split(single_space_pattern, -1).each do |word|
                if line_acc
                  sep = if !first_word
                    " "
                  else
                    ""
                  end

                  if @line_max && line_acc.size + sep.size + word.size > @line_max
                    # Emit the accumulator and move on to building the next line.
                    acc += emit_line(line_acc)
                  else
                    # Accumulate the word.
                    line_acc += sep + word
                    first_word = false

                    next
                  end
                end

                # Trim the word down to size.
                while @line_max && word.size > @line_max
                  acc += emit_line("#{word[0...(@line_max - 1)]}-")
                  word = word[(@line_max - 1)...(word.size)]
                end

                line_acc = word
                first_word = false
              end

              first_line = false
            end
          when REXML::Element
            case node.name
            when "nobreak"
              first_line = true

              (node.text || "").split("\n", -1).each do |line|
                if !first_line
                  acc += emit_line(line_acc || "")
                  line_acc = nil
                end

                if line_acc
                  if @line_max && line_acc.size + line.size > @line_max
                    # Emit the accumulator and move on to building the next line.
                    acc += emit_line(line_acc)
                  else
                    # Accumulate the line.
                    line_acc += line
                    first_line = false

                    next
                  end
                end

                # Trim the line down to size.
                while @line_max && line.size > @line_max
                  acc += emit_line("#{line[0...(@line_max - 1)]}-")
                  line = line[(@line_max - 1)...(line.size)]
                end

                line_acc = line
                first_line = false
              end
            else
              raise "Invalid node name #{node.name.dump}"
            end
          else
            raise "Invalid node class #{node.class.name.dump}"
          end
        end

        acc += emit_line(line_acc) \
          if line_acc

        acc += "#{@footer}\n" \
          if @footer

        acc
      end

      private

      # Emits a single line of output.
      def emit_line(word)
        if @line_max
          "#{@line_header}#{word}#{" " * (@line_max - word.size)}#{@line_footer}\n"
        else
          "#{@line_header}#{word}\n"
        end
      end
    end

    # Some helpers to reduce boilerplate in Rake tasks.
    module RakeHelpers
      module InstanceMethods
        # Runs the given block as a particular user and group.
        def as_user(user = ENV.fetch("SUDO_USER", nil), group = nil, &block)
          _, exit_status = Process.waitpid2(fork do
            Process.gid = Process.egid = Etc.getgrnam(group).gid \
              if group

            Process.uid = Process.euid = Etc.getpwnam(user).uid \
              if user

            block.call

            exit!(0)
          end)

          raise "Child process exited with nonzero status" \
            if exit_status != 0
        end

        # Normalize the given target-dependency specification.
        def normalize_target_deps(target_deps)
          if target_deps.is_a?(Hash)
            raise ArgumentError, "Invalid target-dependency specification" \
              if target_deps.size != 1

            target, deps = target_deps.each_pair.first
          else
            target = target_deps
            deps = []
          end

          deps = [deps] \
            if !deps.is_a?(Array)

          [target, deps]
        end

        # A task for creating a writeable directory along with any missing parent directories.
        def recursive_writeable_directories(target_deps)
          target, deps = normalize_target_deps(target_deps)

          return nil \
            if target.directory? || Rake::Task.task_defined?(target.to_s)

          raise "Target must be a directory" \
            if target.exist?

          parent_task = recursive_writeable_directories target.parent

          task_deps = if parent_task
            deps + [parent_task]
          else
            deps
          end

          directory target.to_s => task_deps do
            as_user("root") do
              mkdir target

              # Set group writeability and ownership to the `admin` group, which the user is presumed to be a member of.
              chmod 0o775, target
              chown nil, "admin", target
            end
          end
        end

        # Creates a writeable directory along with any missing parent directories.
        def create_recursive_writeable_directories(directory)
          if directory.directory?
            return nil
          end

          create_recursive_writeable_directories(directory.parent)

          as_user("root") do
            mkdir directory

            # Set group writeability and ownership to the `admin` group, which the user is presumed to be a member of.
            chmod 0o775, directory
            chown nil, "admin", directory
          end

          directory
        end

        # A task for creating a file along with any missing parent directories.
        def file_with_parent_directories(target_deps, &block)
          target, deps = normalize_target_deps(target_deps)

          parent_task = recursive_writeable_directories target.parent

          task_deps = if parent_task
            deps + [parent_task]
          else
            deps
          end

          file target => task_deps, &block
        end

        # Installs the command-line tools package via the `softwareupdate` tool.
        def softwareupdate_install
          # Ensures that the magic file for faking an on-demand installation is in place. See
          # `http://macops.ca/installing-command-line-tools-automatically-on-mavericks/`.
          magic_temp_file = Pathname.new("/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress")

          pp(:info, "Run `softwareupdate` to get the manifest of available updates")

          touch magic_temp_file

          label_pattern = Regexp.new("\\A\\* Label: (?<identifier>Command Line Tools.*)-(?<display_version>.+)\\z")

          begin
            identifier, display_version = IO.popen(["softwareupdate", "-l"], &:read).
              split("\n").
              map do |line|
                if m = label_pattern.match(line)
                  [m["identifier"], Gem::Version.new(m["display_version"])]
                else
                  nil
                end
              end.
              select { |tuple| tuple }.
              min do |(_, l_version), (_, r_version)|
                -(l_version <=> r_version)
              end

            if !identifier
              raise "Could not find the necessary metadata for installing the command-line tools package"
            end

            package_name = "#{identifier}-#{display_version}"

            pp(:info, "Install #{package_name} via `softwareupdate`")

            sh "softwareupdate", "-i", package_name
          ensure
            rm magic_temp_file
          end
        end

        # Installs the given gem.
        def gem_install(rbenv_root, gem)
          pp(:info, "Install the `#{gem}` gem")

          as_user do
            # Change the directory to avoid picking up any stray `.ruby-version` files.
            cd Pathname.new("/") do
              rbenv(rbenv_root) do |rbenv|
                sh rbenv, "exec", "gem", "install", "--no-document", gem
                sh rbenv, "rehash"
              end
            end
          end
        end

        # Sets up a special environment for rbenv to run in.
        def rbenv(rbenv_root, &block)
          # Set special values for certain rbenv environment variables, run the given block, and restore them
          # afterwards.
          ENV["RBENV_ROOT"], ENV["RBENV_DIR"], ENV["RBENV_HOOK_PATH"], ENV["RBENV_VERSION"] =
            [ENV.fetch("RBENV_ROOT", nil), ENV.fetch("RBENV_DIR", nil), ENV.fetch("RBENV_HOOK_PATH", nil),
             ENV.fetch("RBENV_VERSION", nil)].tap do
               ENV["RBENV_ROOT"] = rbenv_root.to_s
               ENV["RBENV_DIR"] = nil
               ENV["RBENV_HOOK_PATH"] = nil
               ENV["RBENV_VERSION"] = nil
               block.call(rbenv_root.join("bin/rbenv").to_s)
             end
        end

        # Sets up a special environment for Git's SSH protocol.
        def git_ssh(git_ssh_executable, &block)
          # Set environment variables that direct Git to use the provided SSH wrapper, and restore them afterwards.
          ENV["SSH_AUTH_SOCK"], ENV["GIT_SSH"] = [ENV.fetch("SSH_AUTH_SOCK", nil), ENV.fetch("GIT_SSH", nil)].tap do
            ENV["SSH_AUTH_SOCK"] = nil
            ENV["GIT_SSH"] = git_ssh_executable.to_s
            block.call
          end
        end

        # Pretty prints the given message.
        def pp(type = nil, message = nil)
          if type
            case type
            when :info
              message = message.encode(xml: :text)
            end

            puts Rake.application.formatters[type].format(message)
          else
            puts
          end
        end

        # Extracts Chef attributes from the given YAML file or directory hierarchy of files.
        def attributes_from_path(path)
          attributes = {}
          attribute_files = []

          if path.directory? && !path.symlink?
            path.children.each do |child|
              child_attributes, child_attribute_files = attributes_from_path(child)

              if child.directory?
                child_key = child.basename.to_s
                attributes[child_key] = deep_merge(attributes[child_key] || {}, child_attributes)
              else
                attributes = deep_merge(attributes, child_attributes)
              end

              attribute_files += child_attribute_files
            end
          elsif path.file? && path.extname == ".yml"
            attributes = YAML.safe_load(path.open("rb", &:read)) || {}
            attribute_files.push(path)
          end

          [attributes, attribute_files]
        end

        # Deep merges the given `Hash`es.
        def deep_merge(lhs, rhs)
          if lhs.is_a?(Hash) && rhs.is_a?(Hash)
            lhs.merge(rhs) { |_, lhs_value, rhs_value| deep_merge(lhs_value, rhs_value) }
          else
            rhs
          end
        end
      end

      def self.included(klass)
        Rake::Application.class_eval do
          attr_accessor :formatters
        end

        klass.send(:include, InstanceMethods)
      end
    end

    class << self
      attr_reader :define_rake_tasks
    end

    @define_rake_tasks = proc do |opts, user_opts|
      prefix = opts[:prefix]
      ssh_key_file = opts[:ssh_key_file]
      chef_attribute_path = opts[:chef_attribute_path]
      rbenv_dir = opts[:rbenv_dir]
      rbenv_version = opts[:rbenv_version]
      repo_url = opts[:repo_url]
      repo_branch = opts[:repo_branch]
      repo_dir = opts[:repo_dir]
      os_bootstrap_executable = prefix.join("bin/os-bootstrap")

      namespace :os_bootstrap do
        user_data_dir = prefix.join("var/user_data")
        receipts_dir = user_data_dir.join("receipts")
        installed_receipts_dir = receipts_dir.join("installed-receipts-dir")
        installed_command_line_tools = receipts_dir.join("installed-command-line-tools")
        installed_rbenv = receipts_dir.join("installed-rbenv")
        git_ssh_executable = user_data_dir.join("bin/git-ssh")
        chef_config_file = repo_dir.join("config/client.rb")
        installed_user = receipts_dir.join("installed-user-#{repo_dir.basename}")

        task :always_run

        file_with_parent_directories installed_receipts_dir do
          create_recursive_writeable_directories(receipts_dir)

          touch installed_receipts_dir, verbose: false
        end

        namespace :ssh do
          if ssh_key_file
            installed_key_file = user_data_dir.join("ssh", ssh_key_file.basename)

            if installed_key_file != ssh_key_file
              file_with_parent_directories installed_key_file => ssh_key_file do
                pp(:info, "Write the SSH private key file to #{installed_key_file}")

                as_user do
                  # Copy the private key file and secure the copy.
                  cp ssh_key_file, installed_key_file
                  chmod 0o600, installed_key_file

                  # Convert OpenSSH private keys to RSA format (see `https://github.com/net-ssh/net-ssh/issues/633`).
                  sh "ssh-keygen", "-p", "-N", "", "-m", "pem", "-f", installed_key_file.to_s
                end
              end
            end

            installed_key_deps = [installed_key_file]
          else
            installed_key_file = nil
            installed_key_deps = []
          end

          desc "Writes a Git SSH wrapper executable to #{git_ssh_executable.to_s.dump}"
          file_with_parent_directories git_ssh_executable => [installed_receipts_dir] + installed_key_deps do
            ssh_command = ["ssh", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
            ssh_command += ["-i", installed_key_file.to_s] \
              if installed_key_file
            ssh_command = ssh_command.map { |arg| Shellwords.escape(arg) }.join(" ")

            as_user do
              git_ssh_executable.open("wb") do |f|
                f.write(<<EOS
#!/usr/bin/env bash
#
# This script was auto-generated by OS Bootstrap.

# Bail on any errors.
set -e

exec -- #{ssh_command} "$@"
EOS
                       )
              end

              # Assign executable bits.
              chmod "+x", git_ssh_executable

              touch git_ssh_executable
            end
          end
        end

        namespace :command_line_tools do
          clt_bom_file = Pathname.new("/Library/Apple/System/Library/Receipts/com.apple.pkg.CLTools_Executables.bom")

          file clt_bom_file do
            softwareupdate_install
          end

          file_with_parent_directories installed_command_line_tools => [
            clt_bom_file, installed_receipts_dir
          ] do
            as_user do
              touch installed_command_line_tools
            end
          end
        end

        namespace :rbenv do
          ruby_build_dir = rbenv_dir.join("plugins/ruby-build")
          installed_rbenv_repo_dir = receipts_dir.join("installed-rbenv-repo-dir")
          installed_rbenv_repo = receipts_dir.join("installed-rbenv-repo")
          installed_ruby_build_repo = receipts_dir.join("installed-ruby-build-repo")

          file_with_parent_directories installed_rbenv_repo_dir do
            create_recursive_writeable_directories(rbenv_dir)

            # The user must own this directory so as not to trip Git's `safe.directory` protections.
            chown_R ENV.fetch("SUDO_USER", nil), nil, rbenv_dir

            touch installed_rbenv_repo_dir, verbose: false
          end

          desc "Clones the rbenv repository into #{rbenv_dir.to_s.dump}"
          file_with_parent_directories installed_rbenv_repo => [
            installed_command_line_tools, installed_rbenv_repo_dir
          ] do
            pp(:info, "Clone the rbenv repository")

            as_user do
              cd rbenv_dir do
                sh "git", "init"

                sh "git", "remote", "add", "-m", "master", "--", "origin",
                   "https://github.com/rbenv/rbenv" do
                     # Swallow a nonzero exit status.
                   end

                sh "git", "fetch", "--", "origin"

                sh "git", "checkout", "master"
              end

              touch installed_rbenv_repo
            end
          end

          desc "Clones the ruby-build repository into #{ruby_build_dir.to_s.dump}"
          file_with_parent_directories installed_ruby_build_repo => [
            installed_command_line_tools, installed_rbenv_repo
          ] do
            pp(:info, "Clone the ruby-build repository")

            as_user do
              mkdir_p ruby_build_dir

              cd ruby_build_dir do
                sh "git", "init"

                sh "git", "remote", "add", "-m", "master", "--", "origin",
                   "https://github.com/rbenv/ruby-build" do
                     # Swallow a nonzero exit status.
                   end

                sh "git", "fetch", "--", "origin"

                sh "git", "checkout", "master"
                # This is the last known compiling version of OpenSSL, version 1.1.1n. The newer 1.1.1q version is
                # broken: https://github.com/rbenv/ruby-build/discussions/1990.
                sh "git", "reset", "--hard", "v20220630"
              end

              touch installed_ruby_build_repo
            end
          end

          desc "Installs the default rbenv Ruby"
          file_with_parent_directories installed_rbenv => [installed_ruby_build_repo] do
            pp(:info, "Install rbenv Ruby version #{rbenv_version}")

            as_user do
              rbenv(rbenv_dir) do |rbenv|
                sh rbenv, "install", "-s", rbenv_version
              end

              # Set the default rbenv Ruby version.
              rbenv_dir.join("version").open("wb") { |f| f.write("#{rbenv_version}\n") }

              touch installed_rbenv
            end
          end
        end

        namespace :chef do
          installed_attribute_json_file = user_data_dir.join("chef/attributes.json")
          installed_attribute_yaml_file = user_data_dir.join("chef/attributes.yml")
          installed_user_repo_dir = receipts_dir.join("installed-user-repo-dir-#{repo_dir.basename}")
          installed_user_repo = receipts_dir.join("installed-user-repo-#{repo_dir.basename}")
          cheffile_lock = repo_dir.join("Cheffile.lock")
          chef_client_executable = rbenv_dir.join("versions/#{rbenv_version}/bin/chef-client")
          librarian_chef_executable = rbenv_dir.join("versions/#{rbenv_version}/bin/librarian-chef")

          if chef_attribute_path
            attributes, deps = attributes_from_path(chef_attribute_path)

            deps.each { |dep| file dep }

            file_with_parent_directories installed_attribute_json_file => deps do
              pp(:info, "Write the JSONified Chef attribute file to #{installed_attribute_json_file}")

              as_user do
                installed_attribute_json_file.open("wb") { |f| f.write(JSON.generate(attributes)) }
              end
            end

            if !deps.find { |dep| dep == installed_attribute_yaml_file }
              file_with_parent_directories installed_attribute_yaml_file => deps do
                pp(:info, "Write the YAMLized Chef attribute file to #{installed_attribute_yaml_file}")

                as_user do
                  installed_attribute_yaml_file.open("wb") { |f| f.write(YAML.dump(attributes)) }
                end
              end
            end

            installed_attribute_deps = [installed_attribute_json_file, installed_attribute_yaml_file]
          else
            installed_attribute_deps = []
          end

          file_with_parent_directories installed_user_repo_dir do
            create_recursive_writeable_directories(repo_dir)

            # The user must own this directory so as not to trip Git's `safe.directory` protections.
            chown_R ENV.fetch("SUDO_USER", nil), nil, repo_dir

            touch installed_user_repo_dir, verbose: false
          end

          desc "Clones the user's Chef repository into #{repo_dir.to_s.dump}"
          file_with_parent_directories installed_user_repo => [
            installed_command_line_tools, git_ssh_executable, installed_user_repo_dir
          ] do
            pp(:info, "Clone the Chef repository at #{repo_url} (#{repo_branch})")

            as_user do
              git_ssh(git_ssh_executable) do
                cd repo_dir do
                  sh "git", "init"

                  sh "git", "remote", "add", "-m", repo_branch, "--", "origin", repo_url do
                    # Swallow a nonzero exit status.
                  end

                  sh "git", "fetch", "--", "origin"

                  sh "git", "checkout", repo_branch
                end
              end

              raise "Please provide a Chef client configuration file located at #{chef_config_file.to_s.dump}" \
                if !chef_config_file.exist?

              raise "Please provide a `Cheffile.lock` located at #{cheffile_lock.to_s.dump}" \
                if !cheffile_lock.exist?

              touch installed_user_repo
            end
          end

          file chef_client_executable => [installed_rbenv] do
            gem_install(rbenv_dir, "chef:< 15")
          end

          file librarian_chef_executable => [installed_rbenv] do
            gem_install(rbenv_dir, "librarian-chef")
          end

          desc "Runs `librarian-chef install` in the Chef repository"
          file_with_parent_directories installed_user => [
            installed_user_repo, chef_client_executable, librarian_chef_executable
          ] + installed_attribute_deps do
            pp(:info, "Run `librarian-chef install` in the Chef repository")

            as_user do
              cd repo_dir do
                rbenv(rbenv_dir) do |rbenv|
                  git_ssh(git_ssh_executable) do
                    sh rbenv, "exec", "librarian-chef", "install"
                  end
                end
              end

              touch installed_user
            end
          end
        end

        desc "Writes an executable to #{os_bootstrap_executable.to_s.dump}"
        file_with_parent_directories os_bootstrap_executable => [
          installed_rbenv, installed_command_line_tools, installed_user, git_ssh_executable,
          # We need to always run this because the user repo URL may change.
          :always_run
        ] do
          rbenv_executable = rbenv_dir.join("bin/rbenv")

          lines = []
          lines.push(["chef-client", "-z"])
          lines.push(["-c", chef_config_file.to_s])
          lines.push(["-j", user_data_dir.join("chef/attributes.json").to_s]) \
            if chef_attribute_path

          sudo_user_command = "sudo -E -u #{Shellwords.escape(ENV.fetch("SUDO_USER", nil))}"

          chef_client_command = lines.map do |args|
            args.map do |arg|
              Shellwords.escape(arg)
            end.join(" ")
          end.join(" \\\n            ")

          lines = [["--"]]
          lines.push(["--prefix", user_opts[:prefix].realpath.to_s]) \
            if user_opts[:prefix]
          lines.push(["--config-dir", user_opts[:config_dir].realpath.to_s]) \
            if user_opts[:config_dir]
          lines.push(["--rbenv-dir", user_opts[:rbenv_dir].realpath.to_s]) \
            if user_opts[:rbenv_dir]
          lines.push(["--rbenv-version", user_opts[:rbenv_version]]) \
            if user_opts[:rbenv_version]
          lines.push(["--branch", user_opts[:repo_branch]]) \
            if user_opts[:repo_branch]
          lines.push(["--ssh-key", user_opts[:ssh_key_file].realpath.to_s]) \
            if user_opts[:ssh_key_file]
          lines.push(["--chef-attribute-path", user_opts[:chef_attribute_path].realpath.to_s]) \
            if user_opts[:chef_attribute_path]
          lines.push(["--yes"]) \
            if user_opts[:yes_to_all]
          lines.push(["--verbose"]) \
            if user_opts[:verbose]
          lines.push(["--", user_opts[:repo_url]]) \
            if user_opts[:repo_url]

          cached_installer_args = lines.map do |args|
            args.map do |arg|
              Shellwords.escape(arg)
            end.join(" ")
          end.join(" \\\n                ")

          as_user do
            os_bootstrap_executable.open("wb") do |f|
              f.write(<<EOS
#!/usr/bin/env bash
#
# This script was auto-generated by OS Bootstrap.

# Bail on any errors.
set -e

if (( $EUID != 0 )); then
    echo "This script requires root privileges to run" >&2
    exit -- 1
fi

export -- RBENV_ROOT=#{Shellwords.escape(rbenv_dir.to_s)}

# Take no chances and regenerate the `PATH` environment variable.
eval -- "$(PATH="" /usr/libexec/path_helper)"
PATH=#{Shellwords.escape(rbenv_dir.join("bin").to_s)}"${PATH:+":${PATH}"}"
PATH=#{Shellwords.escape(rbenv_dir.join("shims").to_s)}"${PATH:+":${PATH}"}"

# Ensure that SSH authentication works off of the given private key *only*.
unset -- SSH_AUTH_SOCK

# Explicitly set the `RBENV_VERSION` environment variable to override any local versions set in `.ruby-version` files.
export -- RBENV_VERSION=$(rbenv global)

# Direct Git to use the provided SSH wrapper instead of standard `ssh`.
export -- GIT_SSH=#{Shellwords.escape(git_ssh_executable.to_s)}

case "$1" in
    "")
        cd -- #{Shellwords.escape(repo_dir.to_s)}

        sha1_old=$(#{sudo_user_command} -- git rev-parse --verify HEAD)
        #{sudo_user_command} -- git fetch -q
        sha1_new=$(#{sudo_user_command} -- git rev-parse --verify "HEAD@{upstream}")

        # Compare the old and new SHA-1 hashes and only take action if they are different.
        if [[ "$sha1_old" != "$sha1_new" ]]; then
            # Hard reset to the latest commit.
            #{sudo_user_command} -- git reset -q --hard "$sha1_new"

            if [[ -f "Cheffile" ]]; then
                #{sudo_user_command} -- #{Shellwords.escape(rbenv_executable.to_s)} exec librarian-chef install
            fi
        fi

        # Run the Chef client in local mode (`-z`) and point it to the repository's configuration file (by convention).
        exec -- #{Shellwords.escape(rbenv_executable.to_s)} exec #{chef_client_command}
        ;;

    self-update)
        shift -- 1

        if (( $# == 0 )); then
            # These are the installer's original command-line arguments.
            set #{cached_installer_args}
        fi

        exec -- #{Shellwords.escape(rbenv_executable.to_s)} exec ruby \\
            -e "$(curl -fsSL -- "https://raw.githubusercontent.com/carsomyr/os-bootstrap/install/run.rb")" \\
            -- "$@"
        ;;

    *)
        echo "os-bootstrap: Unrecognized subcommand \\`$1\\`" >&2
        exit -- 1
        ;;
esac
EOS
                     )
            end

            # Assign executable bits.
            chmod "+x", os_bootstrap_executable, verbose: false
          end
        end
      end

      task default: os_bootstrap_executable do
        # Display the post-installation notice.
        pp
        pp(:xml_heading, <<EOS
Installation complete!

We've placed the <nobreak>#{os_bootstrap_executable.basename.to_s.encode(xml: :text)}</nobreak> script in <nobreak>\
#{os_bootstrap_executable.dirname.to_s.encode(xml: :text)}</nobreak>. Assuming that it's on your path, you can now run:

    sudo -- <nobreak>#{os_bootstrap_executable.basename.to_s.encode(xml: :text)}</nobreak>

Each invocation will check the repository at\
 <nobreak>#{"#{repo_url} (#{repo_branch})".to_s.encode(xml: :text)}</nobreak>\
 for changes, and, if any, run `librarian-chef install` to update Chef cookbooks.

The `self-update` subcommand will run this installer with its original command-line arguments and regenerate\
 <nobreak>#{os_bootstrap_executable.to_s.encode(xml: :text)}</nobreak>. Consequently, the new instance will take on\
 potentially different settings.

Happy provisioning, and don't hesitate to file issues against the project:

    https://github.com/carsomyr/os-bootstrap
EOS
        )
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  opts = {
    prefix: Pathname.new("/usr/local"),
    config_dir: Pathname.new("/Volumes/User Data"),
    rbenv_dir: Pathname.new("/usr/local/var/rbenv"),
    rbenv_version: "2.7.6",
    repo_url: "https://github.com/carsomyr/os-bootstrap",
    repo_branch: "main",
    ssh_key_file: nil,
    chef_attribute_path: nil,
    verbose: false
  }

  user_opts = {}

  positional_args = OptionParser.new do |opt_spec|
    opt_spec.banner = "usage: #{Pathname.new(__FILE__).basename} [<options>] [[--] <dir>...]"

    opt_spec.separator ""
    opt_spec.separator "optional arguments:"

    opt_spec.on("--prefix PREFIX", "specify the installation prefix") do |prefix|
      user_opts[:prefix] = Pathname.new(prefix)
    end

    opt_spec.on("--config-dir CONFIG_DIR", "specify the configuration directory") do |config_dir|
      user_opts[:config_dir] = Pathname.new(config_dir)
    end

    opt_spec.on("--rbenv-dir RBENV_DIR", "specify the rbenv installation directory") do |rbenv_dir|
      user_opts[:rbenv_dir] = Pathname.new(rbenv_dir)
    end

    opt_spec.on("--rbenv-version RBENV_VERSION", "specify the default rbenv Ruby version") do |rbenv_version|
      user_opts[:rbenv_version] = rbenv_version
    end

    opt_spec.on("-b", "--branch BRANCH", "specify the Chef repository branch to checkout") do |repo_branch|
      user_opts[:repo_branch] = repo_branch
    end

    opt_spec.on("-k", "--ssh-key SSH_KEY", "provide an SSH private key") do |ssh_key_file|
      user_opts[:ssh_key_file] = Pathname.new(ssh_key_file)
    end

    opt_spec.on("-c", "--chef-attribute-path CHEF_ATTRIBUTE_PATH", "provide a `chef-client` attribute file in YAML or" \
      " as a directory hierarchy of files") do |chef_attribute_path|
        user_opts[:chef_attribute_path] = Pathname.new(chef_attribute_path)
      end

    opt_spec.on("-y", "--yes", "a non-interactive \"yes\" answer to all prompts") do
      user_opts[:yes_to_all] = true
    end

    opt_spec.on("-v", "--verbose", "be verbose") do
      user_opts[:verbose] = true
    end
  end.parse(ARGV)

  case positional_args.size
  when 1
    user_opts[:repo_url] = positional_args.first
  when 0
    # Use default values.
  else
    raise "Please specify exactly one Git repository"
  end

  opts = opts.merge(user_opts)

  # Mix in our helpers.
  class << self
    include Os::Bootstrap::RakeHelpers
  end

  if $stdout.tty?
    tty_blue = "\033[34m"
    tty_green = "\033[32m"
    tty_reset = "\033[0m"
  else
    tty_blue = ""
    tty_green = ""
    tty_reset = ""
  end

  # Set the pretty print formatters.
  Rake.application.formatters = {
    xml_heading: Os::Bootstrap::Formatter.new(
      "#{tty_blue}*#{"-" * 118}*#{tty_reset}",
      "#{tty_blue}*#{"-" * 118}*#{tty_reset}",
      "#{tty_blue}|#{tty_reset} ", " #{tty_blue}|#{tty_reset}", 116
    ),
      info: Os::Bootstrap::Formatter.new(
        "", "", " #{tty_green}=>#{tty_reset} "
      )
  }

  prefix = opts[:prefix]
  config_dir = opts[:config_dir]
  ssh_key_file = opts[:ssh_key_file]
  chef_attribute_path = opts[:chef_attribute_path]
  rbenv_dir = opts[:rbenv_dir]
  rbenv_version = opts[:rbenv_version]
  yes_to_all = opts[:yes_to_all]
  repo_url = opts[:repo_url]
  repo_branch = opts[:repo_branch]

  existing_install_dir = prefix.join("var/user_data")

  config_dir = existing_install_dir \
    if !config_dir.directory? && existing_install_dir.directory?

  if !ssh_key_file
    ssh_key_file = Pathname.glob("#{config_dir}/ssh/id_{rsa,dsa,ecdsa}").first
    opts[:ssh_key_file] = ssh_key_file
  end

  raise "No SSH private key file found at #{ssh_key_file.to_s.dump}" \
    if ssh_key_file && !ssh_key_file.file?

  chef_attribute_dir = config_dir.join("chef")

  if !chef_attribute_path && chef_attribute_dir.directory?
    chef_attribute_path = chef_attribute_dir
    opts[:chef_attribute_path] = chef_attribute_path
  end

  raise "No Chef attributes found at #{chef_attribute_path.to_s.dump}" \
    if chef_attribute_path && !chef_attribute_path.exist?

  repo_basename_pattern = Regexp.new("\\A.+[/:](.+)\\z")
  m = repo_basename_pattern.match(repo_url)

  raise "Invalid Git repository URL #{repo_url.dump}" \
    if !m

  opts[:repo_dir] = prefix.join(
    "var/user_data/git/#{m[1]}-#{Digest::SHA1.hexdigest("#{repo_url}##{repo_branch}")[0...7]}"
  )

  pp(:xml_heading, <<EOS
Hello from the OS Bootstrap installer!

We're just a few minutes away from provisioning your machine with Chef. Before proceeding, please confirm these\
 settings.

Chef repository:
    <nobreak>#{"#{repo_url} (#{repo_branch})".encode(xml: :text)}</nobreak>

SSH private key:
    <nobreak>#{((ssh_key_file && ssh_key_file.to_s) || "(not found)").encode(xml: :text)}</nobreak>

Chef attribute path<nobreak>#{((chef_attribute_path && " (#{chef_attribute_path.ftype})") || "").encode(xml: :text)}\
</nobreak>:
    <nobreak>#{((chef_attribute_path && chef_attribute_path.to_s) || "(not found)").encode(xml: :text)}</nobreak>

install prefix:
    <nobreak>#{prefix.to_s.encode(xml: :text)}</nobreak>

rbenv root:
    <nobreak>#{rbenv_dir.to_s.encode(xml: :text)}</nobreak>

rbenv version:
    <nobreak>#{rbenv_version.encode(xml: :text)}</nobreak>

You can rerun this script with `-h` to get a menu of command-line options for overriding any of the above.
EOS
  )
  pp

  if !yes_to_all
    print "\n #{tty_green}=>#{tty_reset} Do you wish to continue (y/n)? "

    answer = $stdin.getc

    print "\n"

    if answer != "y"
      if $stdin.tty?
        pp(:info, "Installation not attempted.")
      else
        pp(:info, "Installation not attempted. If you are running this script non-interactively, consider providing" \
          " the `-y` flag option.")
      end

      exit 1
    end
  end

  raise "Root privileges are needed" \
    if Process.euid != 0

  instance_exec(opts, user_opts, &Os::Bootstrap.define_rake_tasks).invoke
end
