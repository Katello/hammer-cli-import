require 'hammer_cli'
require 'hammer_cli_import'

module HammerCLIImport
  class ImportCommand
    class DirCommand < HammerCLI::AbstractCommand
      command_name 'dir'
      desc 'Load data from a specified DIRectory that is in stargate-export format'

      option ['--directory'], 'DIR_PATH', 'stargate-export directory', :default => '/tmp/exports'
      option ['--entities'], 'entity[,entity...]', 'Import specific entities', :default => 'all'
      option ['--list-entities'], :flag, 'List entities we understand', :default => false
      option ['--dry-run'], :flag, 'Show what we would have done, if we\'d been allowed', :default => false

      @@entity_order = ['organizations', 'users', 'system-groups', 'repositories']
      #
      # A list of what we know how to do.
      # The map has entries of
      #   import-entity => {sat5-export-name, import-classname, should-import}
      # The code will look for classes HammerCLIImport::ImportCommand::<import-classname>
      # It will look in ~/exports/<Sat5-export-name>.csv for data
      #
      @@known = { 'system-groups' =>
                    {'export-file' => 'system-groups',
                     'import-class' => 'SystemGroupImportCommand',
                     'import' => false },
                  'organizations' =>
                    {'export-file' => 'users',
                     'import-class' => 'OrganizationImportCommand',
                     'import' => false },
                  'users' =>
                    {'export-file' => 'users',
                     'import-class' => 'UserImportCommand',
                     'import' => false },
                  'repositories' =>
                    {'export-file' => 'repositories',
                     'import-class' => 'RepositoryImportCommand',
                     'import' => false }
                  #'custom-channels' =>
                  #  {'export-file' => 'system-groups',
                  #   'import-class' => 'SystemGroupImportCommand',
                  #   'import' => false },
                }

      def do_list
        puts 'Entities I understand:'
        @@entity_order.each do |key|
          puts "  #{key}"
        end
      end

      # What are we being asked to import?
      def set_import_targets
        to_import = option_entities.split(',')

        @@known.each_key do |key|
          @@known[key]['import'] = (to_import.include?(key) or to_import.include?('all'))
        end
      end

      # Do the import(s)
      def import_from
        @@entity_order.each do |key|
          a_map = @@known[key]
          import_file = "#{option_directory}/#{a_map['export-file']}.csv"
          if a_map['import']
            puts "IMPORT #{key} FROM #{import_file}"
            args = ['--csv-file', import_file]

            #############################################################
            # MAGIC! We create a class from the class-name-string here! #
            #############################################################
            import_class = HammerCLIImport::ImportCommand.const_get(a_map['import-class'])
            if ! option_dry_run?
              import_class.new(args).run(args)
            end
          end
        end
      end

      def execute
        if option_list_entities?
          do_list
          exit 0
        end

        set_import_targets
        import_from
        HammerCLI::EX_OK
      end
    end
  end
end


