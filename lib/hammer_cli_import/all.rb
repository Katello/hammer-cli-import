#
# Copyright (c) 2014 Red Hat Inc.
#
# This file is part of hammer-cli-import.
#
# hammer-cli-import is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# hammer-cli-import is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with hammer-cli-import.  If not, see <http://www.gnu.org/licenses/>.
#

require 'hammer_cli'
require 'hammer_cli_import'

module HammerCLIImport
  class ImportCommand
    class AllCommand < HammerCLI::AbstractCommand
      extend ImportTools::Repository::Extend
      extend ImportTools::ImportLogging::Extend
      extend AsyncTasksReactor::Extend
      include ImportTools::ImportLogging::Include

      command_name 'all'
      desc 'Load ALL data from a specified directory that is in spacewalk-export format.'

      option ['--directory'], 'DIR_PATH', 'stargate-export directory', :default => '/tmp/exports'
      option ['--delete'], :flag, 'Delete entities instead of importing them', :default => false
      option ['--manifest-directory'], 'DIR_PATH', 'Directory holding manifests'
      option ['--entities'], 'entity[,entity...]', 'Import specific entities', :default => 'all'
      option ['--list-entities'], :flag, 'List entities we understand', :default => false
      option ['--into-org-id'], 'ORG_ID', 'Import all organizations into one specified by id'
      option ['--merge-users'], :flag, 'Merge pre-created users (except admin)', :default => false
      option ['--dry-run'], :flag, 'Show what we would have done, if we\'d been allowed', :default => false

      add_repo_options
      add_logging_options

      # An ordered-list of the entities we know how to import
      class << self; attr_accessor :entity_order end
      @entity_order = %w(organization user host-collection repository-enable repository
                         content-view activation-key template-snippet config-file content-host)

      #
      # A list of what we know how to do.
      # The map has entries of
      #   import-entity => {sat5-export-name, import-classname, entities-we-are-dependent-on, should-import}
      # The code will look for classes HammerCLIImport::ImportCommand::<import-classname>
      # It will look in ~/exports/<Sat5-export-name>.csv for data
      #
      class << self; attr_accessor :known end
      @known = {
        'activation-key' =>
                    {'export-file' => 'activation-keys',
                     'import-class' => 'ActivationKeyImportCommand',
                     'depends-on' => 'organization',
                     'import' => false },
        'config-file' =>
                    {'export-file' => 'config-files-latest',
                     'import-class' => 'ConfigFileImportCommand',
                     'depends-on' => 'organization',
                     'import' => false },
        'content-host' =>
                    {'export-file' => 'system-profiles',
                     'import-class' => 'ContentHostImportCommand',
                     'depends-on' => 'content-view,host-collection,repository,organization',
                     'import' => false },
        'content-view' =>
                    {'export-file' => 'CHANNELS/export',
                     'import-class' => 'LocalRepositoryImportCommand',
                     'depends-on' => 'repository,organization',
                     'import' => false },
        'repository' =>
                    {'export-file' => 'repositories',
                     'import-class' => 'RepositoryImportCommand',
                     'depends-on' => 'organization',
                     'import' => false },
        'host-collection' =>
                    {'export-file' => 'system-groups',
                     'import-class' => 'SystemGroupImportCommand',
                     'depends-on' => 'organization',
                     'import' => false },
        'organization' =>
                    {'export-file' => 'users',
                     'import-class' => 'OrganizationImportCommand',
                     'depends-on' => '',
                     'import' => false },
        'repository-enable' =>
                    {'export-file' => 'channels',
                     'import-class' => 'RepositoryEnableCommand',
                     'depends-on' => 'organization',
                     'import' => false },
        'template-snippet' =>
                    {'export-file' => 'kickstart-scripts',
                     'import-class' => 'TemplateSnippetImportCommand',
                     'import' => false },
        'user' =>
                    {'export-file' => 'users',
                     'import-class' => 'UserImportCommand',
                     'depends-on' => 'organization',
                     'import' => false }
      }

      def do_list
        puts 'Entities I understand:'
        AllCommand.entity_order.each do |an_entity|
          puts "  #{an_entity}"
        end
      end

      # What are we being asked to import?
      # Marks what we asked for, and whatever those things are dependent on, to import
      def set_import_targets
        to_import = option_entities.split(',')
        AllCommand.known.each_key do |key|
          AllCommand.known[key]['import'] = (to_import.include?(key) || to_import.include?('all'))
          next if AllCommand.known[key]['depends-on'].nil? || !AllCommand.known[key]['import']

          depends_on = AllCommand.known[key]['depends-on'].split(',')
          depends_on.each do |entity_name|
            AllCommand.known[entity_name]['import'] = true
          end
        end
      end

      # config-file may need --macro-mapping
      def config_file_args(args)
        args << '--macro-mapping' << "#{option_macro_mapping}" unless option_macro_mapping.nil?
        return args
      end

      # 'content-host needs --export-directory
      def content_host_args(args)
        args << '--export-directory' << File.join(File.expand_path('~'), 'rpm-working-dir')
        return args
      end

      # 'content-view needs --dir, and knows its own --csv-file in that dir
      def content_view_args(args)
        args << '--dir' << "#{option_directory}/CHANNELS"
        return args
      end

      # 'organization' may need --into-org-id
      def organization_args(args)
        args << '--into-org-id' << option_into_org_id unless option_into_org_id.nil?
        args << '--upload-manifests-from' << option_manifest_directory unless option_manifest_directory.nil?
        return args
      end

      # repository and repo-enable may need --synch and --wait
      def repository_args(args)
        args << '--synchronize' if option_synchronize?
        args << '--wait' if option_wait?
        return args
      end

      # 'user' needs --new-passwords and may need --merge-users
      def user_args(args)
        pwd_filename = "passwords_#{Time.now.utc.iso8601}.csv"
        args << '--new-passwords' << pwd_filename
        args << '--merge-users' if option_merge_users?
        return args
      end

      # Some subcommands have their own special args
      # This is the function that will know them all
      def build_args(key, filename)
        if key == 'content-view'
          csv = ['--csv-file', "#{option_directory}/CHANNELS/export.csv"]
        else
          csv = ['--csv-file', filename]
        end
        return csv << '--delete' if option_delete?

        case key
        when 'config-file'
          args = config_file_args(csv)
        when 'content-host'
          args = content_host_args(csv)
        when 'content-view'
          args = content_view_args(csv)
        when 'organization'
          args = organization_args(csv)
        when 'repository', 'repository-enable'
          args = repository_args(csv)
        when 'user'
          args = user_args(csv)
        else
          args = csv
        end
        return args
      end

      # Get entities-to-be-processed, in the right order (reversed if deleting)
      def entities
        if option_delete?
          return AllCommand.entity_order.reverse
        else
          return AllCommand.entity_order
        end
      end

      # Do the import(s)
      def import_from
        entities.each do |key|
          a_map = AllCommand.known[key]
          if a_map['import']
            import_file = "#{option_directory}/#{a_map['export-file']}.csv"
            args = build_args(key, import_file)
            if File.exist? import_file
              progress format('Import %-20s with arguments %s', key, args.join(' '))

              #############################################################
              # MAGIC! We create a class from the class-name-string here! #
              #############################################################
              import_class = HammerCLIImport::ImportCommand.const_get(a_map['import-class'])
              unless option_dry_run?
                import_class.new(args).run(args)
              end
            else
              progress "...SKIPPING, no file #{import_file} available."
            end
          end
        end
      end

      def execute
        setup_logging
        if option_list_entities?
          do_list
        else
          set_import_targets
          import_from
        end
        HammerCLI::EX_OK
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
