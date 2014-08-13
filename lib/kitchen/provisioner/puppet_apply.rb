# -*- encoding: utf-8 -*-
#
# Author:: Chris Lundquist (<chris.lundquist@github.com>) Neill Turner (<neillwturner@gmail.com>)
#
# Copyright (C) 2013,2014 Chris Lundquist, Neill Turner
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# See https://github.com/neillturner/kitchen-puppet/blob/master/provisioner_options.md
# for documentation configuration parameters with puppet_apply provisioner.
#

require 'json'
require 'kitchen/provisioner/base'
require 'kitchen/provisioner/puppet/librarian'

module Kitchen

  class Busser

    def non_suite_dirs
      %w{data data_bags environments nodes roles puppet}
    end
  end

  module Provisioner
    #
    # Puppet Apply provisioner.
    #
    class PuppetApply < Base
      attr_accessor :tmp_dir

      default_config :require_puppet_omnibus, false
      # TODO use something like https://github.com/fnichol/omnibus-puppet
      default_config :puppet_omnibus_url, nil
      default_config :puppet_omnibus_remote_path, '/opt/puppet'
      default_config :puppet_version, nil
      default_config :require_puppet_repo, true
      default_config :puppet_apt_repo, "http://apt.puppetlabs.com/puppetlabs-release-precise.deb"
      default_config :puppet_yum_repo, "https://yum.puppetlabs.com/puppetlabs-release-el-6.noarch.rpm"
      default_config :chef_bootstrap_url, "https://www.getchef.com/chef/install.sh"

      default_config :hiera_data_remote_path, '/var/lib/hiera'
      default_config :manifest, 'site.pp'

      default_config :manifests_path do |provisioner|
        provisioner.calculate_path('manifests') or
          raise 'No manifests_path detected. Please specify one in .kitchen.yml'
      end

      default_config :modules_path do |provisioner|
        modules_path = provisioner.calculate_path('modules')
        if modules_path.nil? && provisioner.calculate_path('Puppetfile', :file).nil?
          raise 'No modules_path detected. Please specify one in .kitchen.yml'
        end
        modules_path
      end

      default_config :files_path do |provisioner|
        provisioner.calculate_path('files') || 'files'
      end

      default_config :hiera_data_path do |provisioner|
        provisioner.calculate_path('hiera')
      end

      default_config :hiera_config_path do |provisioner|
        provisioner.calculate_path('hiera.yaml', :file)
      end

      default_config :fileserver_config_path do |provisioner|
        provisioner.calculate_path('fileserver.conf', :file)
      end

      default_config :puppetfile_path do |provisioner|
        provisioner.calculate_path('Puppetfile', :file)
      end

      default_config :modulefile_path do |provisioner|
        provisioner.calculate_path('Modulefile', :file)
      end

      default_config :metadata_json_path do |provisioner|
        provisioner.calculate_path('metadata.json', :file)
      end

      default_config :manifests_path do |provisioner|
        provisioner.calculate_path('manifests', :directory)
      end


      default_config :puppet_debug, false
      default_config :puppet_verbose, false
      default_config :puppet_noop, false
      default_config :puppet_platform, ''
      default_config :update_package_repos, true
      default_config :custom_facts, {}

      def calculate_path(path, type = :directory)
        base = config[:test_base_path]
        candidates = []
        candidates << File.join(base, instance.suite.name, 'puppet', path)
        candidates << File.join(base, instance.suite.name, path)
        candidates << File.join(base, path)
        candidates << File.join(Dir.pwd, path)

        candidates.find do |c|
          type == :directory ? File.directory?(c) : File.file?(c)
        end
      end

      def install_command
        return unless config[:require_puppet_omnibus] or config[:require_puppet_repo]
        if config[:require_puppet_omnibus]
          info("Installing puppet using puppet omnibus")
          version = if !config[:puppet_version].nil?
            "-v #{config[:puppet_version]}"
          else
            ""
          end
          <<-INSTALL
          #{Util.shell_helpers}

          if [ ! -d "#{config[:puppet_omnibus_remote_path]}" ]; then
            echo "-----> Installing Puppet Omnibus"
            do_download #{config[:puppet_omnibus_url]} /tmp/puppet_install.sh
            #{sudo('sh')} /tmp/puppet_install.sh #{version}
          fi
          #{install_busser}
          INSTALL
        else
          case puppet_platform
          when "debian", "ubuntu"
            info("Installing puppet on #{puppet_platform}")
          <<-INSTALL
          if [ ! $(which puppet) ]; then
            #{sudo('wget')} #{puppet_apt_repo}
            #{sudo('dpkg')} -i #{puppet_apt_repo_file}
            #{update_packages_debian_cmd}
            #{sudo('apt-get')} -y install puppet#{puppet_debian_version}
          fi
          #{install_busser}
          INSTALL
          when "redhat", "centos", "fedora"
            info("Installing puppet on #{puppet_platform}")
          <<-INSTALL
          if [ ! $(which puppet) ]; then
            #{sudo('rpm')} -ivh #{puppet_yum_repo}
                    #{update_packages_redhat_cmd}
            #{sudo('yum')} -y install puppet#{puppet_redhat_version}
          fi
          #{install_busser}
          INSTALL
          when "windows"
            info("Installing puppet on #{puppet_platform}")
          <<-INSTALL
            $webclient = New-Object System.Net.WebClient;  $webclient.DownloadFile('http://downloads.puppetlabs.com/windows/puppet-#{puppet_windows_version}.msi','puppet-#{puppet_windows_version}.msi')
            msiexec /qn /i puppet-#{puppet_windows_version}.msi
            Start-Sleep -s 60

            cmd.exe /C "SET PATH=%PATH%;`"C:\\Program Files (x86)\\Puppet Labs\\Puppet\\bin`""

            #{install_busser}
          INSTALL
         else
          info("Installing puppet, will try to determine platform os")
          <<-INSTALL
          if [ ! $(which puppet) ]; then
            if [ -f /etc/centos-release ] || [ -f /etc/redhat-release ]; then
               #{sudo('rpm')} -ivh #{puppet_yum_repo}
               #{update_packages_redhat_cmd}
               #{sudo('yum')} -y install puppet#{puppet_redhat_version}
            else
               #{sudo('wget')} #{puppet_apt_repo}
               #{sudo('dpkg')} -i #{puppet_apt_repo_file}
               #{update_packages_debian_cmd}
               #{sudo('apt-get')} -y install puppet#{puppet_debian_version}
            fi
          fi
          #{install_busser}
          INSTALL
         end
        end
      end

      def install_command_posh
        install_command
      end

      def init_command_posh

      end

      def install_busser
        info("Install busser on #{puppet_platform}")
        case puppet_platform
        when 'windows'
          #https://raw.githubusercontent.com/opscode/knife-windows/master/lib/chef/knife/bootstrap/windows-chef-client-msi.erb
          <<-INSTALL
           $webclient = New-Object System.Net.WebClient;  $webclient.DownloadFile('https://opscode-omnibus-packages.s3.amazonaws.com/windows/2008r2/x86_64/chef-windows-11.12.8-1.windows.msi','chef-windows-11.12.8-1.windows.msi')
           msiexec /qn /i chef-windows-11.12.8-1.windows.msi

           cmd.exe /C "SET PATH=%PATH%;`"C:\\opscode\\chef\\embedded\\bin`";`"C:\\tmp\\busser\\gems\\bin`""

          INSTALL
        else
          <<-INSTALL
          #{Util.shell_helpers}
          # install chef omnibus so that busser works as this is needed to run tests :(
          # TODO: work out how to install enough ruby
          # and set busser: { :ruby_bindir => '/usr/bin/ruby' } so that we dont need the
          # whole chef client
          if [ ! -d "/opt/chef" ]
          then
            echo "-----> Installing Chef Omnibus to install busser to run tests"
            do_download #{chef_url} /tmp/install.sh
            #{sudo('sh')} /tmp/install.sh
          fi
          INSTALL
        end
      end

        def init_command
          dirs = %w{modules manifests files hiera hiera.yaml}.
            map { |dir| File.join(config[:root_path], dir) }.join(" ")
          cmd = "#{sudo('rm')} -rf #{dirs} #{hiera_data_remote_path} /etc/hiera.yaml /etc/puppet/hiera.yaml /etc/puppet/fileserver.conf;"
          cmd = cmd+" mkdir -p #{config[:root_path]}"
          debug(cmd)
          cmd
        end

        def create_sandbox
          super
          debug("Creating local sandbox in #{sandbox_path}")

          yield if block_given?

          prepare_modules
          prepare_manifests
          prepare_files
          prepare_hiera_config
          prepare_fileserver_config
          prepare_hiera_data
          info('Finished Preparing files for transfer')

        end

        def cleanup_sandbox
          return if sandbox_path.nil?
          debug("Cleaning up local sandbox in #{sandbox_path}")
          FileUtils.rmtree(sandbox_path)
        end

        def prepare_command
          commands = []

          if hiera_config
            commands << [
              sudo('cp'), File.join(config[:root_path],'hiera.yaml'), '/etc/',
            ].join(' ')

            commands << [
              sudo('cp'), File.join(config[:root_path],'hiera.yaml'), '/etc/puppet/',
            ].join(' ')
          end

          if fileserver_config
            commands << [
              sudo('cp'),
              File.join(config[:root_path], 'fileserver.conf'),
              '/etc/puppet',
            ].join(' ')
          end

          if hiera_data and hiera_data_remote_path == '/var/lib/hiera'
            commands << [
              sudo('cp -r'), File.join(config[:root_path], 'hiera'), '/var/lib/'
            ].join(' ')
          end

          if hiera_data and hiera_data_remote_path != '/var/lib/hiera'
            commands << [
              sudo('mkdir -p'), hiera_data_remote_path
            ].join(' ')
                        commands << [
              sudo('cp -r'), File.join(config[:root_path], 'hiera/*'), hiera_data_remote_path
            ].join(' ')
          end

          command = commands.join(' && ')
          debug(command)
          command
        end

        def run_command
          arr = [
            custom_facts,
            sudo('puppet'),
            'apply',
            File.join(config[:root_path], 'manifests', manifest),
            "--modulepath=#{File.join(config[:root_path], 'modules')}",
            "--manifestdir=#{File.join(config[:root_path], 'manifests')}",
            "--fileserverconfig=#{File.join(config[:root_path], 'fileserver.conf')}",
            puppet_noop_flag,
            puppet_verbose_flag,
            puppet_debug_flag
          ].join(" ")
          info(arr)
          "start-job -scriptblock { cmd.exe /c \"#{arr.strip!}\" }"
        end

        protected

        def load_needed_dependencies!
          if File.exists?(puppetfile)
            debug("Puppetfile found at #{puppetfile}, loading Librarian-Puppet")
            Puppet::Librarian.load!(logger)
          end
        end

        def tmpmodules_dir
          File.join(sandbox_path, 'modules')
        end

        def puppetfile
          config[:puppetfile_path] or ''
        end

        def modulefile
          config[:modulefile_path] or ''
        end

        def metadata_json
          config[:metadata_json_path] or ''
        end

        def manifest
          info("LBENNETT test")
          info(config[:manifest])
          info(diagnose)
          config[:manifest]
        end

        def manifests
          config[:manifests_path]
        end

        def modules
          config[:modules_path]
        end

        def files
          config[:files_path] || 'files'
        end

        def hiera_config
          config[:hiera_config_path]
        end

        def fileserver_config
          config[:fileserver_config_path]
        end

        def hiera_data
          config[:hiera_data_path]
        end

        def hiera_data_remote_path
          config[:hiera_data_remote_path]
        end

        def puppet_debian_version
          config[:puppet_version] ? "=#{config[:puppet_version]}" : nil
        end

        def puppet_redhat_version
          config[:puppet_version] ? "-#{config[:puppet_version]}" : nil
        end

        def puppet_windows_version
          config[:puppet_version] ? "#{config[:puppet_version]}" : nil
        end

        def puppet_noop_flag
          config[:puppet_noop] ? '--noop' : nil
        end

        def puppet_debug_flag
          config[:puppet_debug] ? '-d' : nil
        end

        def puppet_verbose_flag
          config[:puppet_verbose] ? '-v' : nil
        end

        def puppet_platform
          config[:puppet_platform].to_s.downcase
        end

        def update_packages_debian_cmd
          config[:update_package_repos] ? "#{sudo('apt-get')} update" : nil
        end

        def update_packages_redhat_cmd
          config[:update_package_repos] ? "#{sudo('yum')} makecache" : nil
        end

        def custom_facts
          return nil if config[:custom_facts].none?
          bash_vars = config[:custom_facts].map { |k,v| "FACTER_#{k}=#{v}" }.join(" ")
          bash_vars = "export #{bash_vars};"
          debug(bash_vars)
          bash_vars
        end

        def puppet_apt_repo
          config[:puppet_apt_repo]
        end

        def puppet_apt_repo_file
          config[:puppet_apt_repo].split('/').last
        end

        def puppet_yum_repo
          config[:puppet_yum_repo]
        end

        def chef_url
          config[:chef_bootstrap_url]
        end

        def prepare_manifests
          info('Preparing manifests')
          debug("Using manifests from #{manifests}")

          tmp_manifests_dir = File.join(sandbox_path, 'manifests')
          FileUtils.mkdir_p(tmp_manifests_dir)
          FileUtils.cp_r(Dir.glob("#{manifests}/*"), tmp_manifests_dir)
        end

        def prepare_files
          info('Preparing files')

          unless File.directory?(files)
            info 'nothing to do for files'
            return
          end

          debug("Using files from #{files}")

          tmp_files_dir = File.join(sandbox_path, 'files')
          FileUtils.mkdir_p(tmp_files_dir)
          FileUtils.cp_r(Dir.glob("#{files}/*"), tmp_files_dir)
        end

        def prepare_modules
          info('Preparing modules')

          FileUtils.mkdir_p(tmpmodules_dir)

          if modules && File.directory?(modules)
            debug("Using modules from #{modules}")
            FileUtils.cp_r(Dir.glob("#{modules}/*"), tmpmodules_dir, remove_destination: true)
          else
            info 'nothing to do for modules'
          end

          resolve_with_librarian if File.exists?(puppetfile)

          copy_self_as_module
        end

        def copy_self_as_module
          if File.exists?(modulefile)
            warn('Modulefile found but this is depricated, ignoring it, see https://tickets.puppetlabs.com/browse/PUP-1188')
          end

          if File.exists?(metadata_json)
            module_name = nil
            begin
              module_name = JSON.parse(IO.read(metadata_json))['name'].split('-').last
            rescue
              error("not able to load or parse #{metadata_json_path} for the name of the module")
            end

            if module_name
              module_target_path = File.join(sandbox_path, 'modules', module_name)
              FileUtils.mkdir_p(module_target_path)
              FileUtils.cp_r(
                Dir.glob(File.join(config[:kitchen_root], '*')).reject { |entry| entry =~ /modules/ },
                module_target_path,
                remove_destination: true
              )
            end
          end
        end

        def prepare_hiera_config
          return unless hiera_config

          info('Preparing hiera')
          debug("Using hiera from #{hiera_config}")

          FileUtils.cp_r(hiera_config, File.join(sandbox_path, 'hiera.yaml'))
        end

        def prepare_fileserver_config
          return unless fileserver_config

          info('Preparing fileserver')
          debug("Using fileserver config from #{fileserver_config}")

          FileUtils.cp_r(fileserver_config, File.join(sandbox_path, 'fileserver.conf'))
        end

        def prepare_hiera_data
          return unless hiera_data
          info('Preparing hiera data')
          debug("Using hiera data from #{hiera_data}")

          tmp_hiera_dir = File.join(sandbox_path, 'hiera')
          FileUtils.mkdir_p(tmp_hiera_dir)
          FileUtils.cp_r(Dir.glob("#{hiera_data}/*"), tmp_hiera_dir)
        end

        def resolve_with_librarian
          Kitchen.mutex.synchronize do
            Puppet::Librarian.new(puppetfile, tmpmodules_dir, logger).resolve
          end
        end
    end
  end
end
