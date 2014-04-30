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

      # An ordered-list of the entities we know how to import
      class << self; attr_accessor :entity_order end
      @entity_order = %w(organizations users system-groups repositories)

      #
      # A list of what we know how to do.
      # The map has entries of
      #   import-entity => {sat5-export-name, import-classname, entities-we-are-dependent-on, should-import}
      # The code will look for classes HammerCLIImport::ImportCommand::<import-classname>
      # It will look in ~/exports/<Sat5-export-name>.csv for data
      #
      class << self; attr_accessor :known end
      @known = { 'system-groups' =>
                    {'export-file' => 'system-groups',
                     'import-class' => 'SystemGroupImportCommand',
                     'depends-on' => 'organizations',
                     'import' => false },
                  'organizations' =>
                    {'export-file' => 'users',
                     'import-class' => 'OrganizationImportCommand',
                     'depends-on' => '',
                     'import' => false },
                  'users' =>
                    {'export-file' => 'users',
                     'import-class' => 'UserImportCommand',
                     'depends-on' => 'organizations',
                     'import' => false },
                  'repositories' =>
                    {'export-file' => 'repositories',
                     'import-class' => 'RepositoryImportCommand',
                     'depends-on' => 'organizations',
                     'import' => false }
                  #'custom-channels' =>
                  #  {'export-file' => 'system-groups',
                  #   'import-class' => 'SystemGroupImportCommand',
                  #   'import' => false },
                }

      def do_list
        puts 'Entities I understand:'
        DirCommand.entity_order.each do |a_map|
          puts "  #{a_map['name']}"
        end
      end

      # What are we being asked to import?
      # Marks what we asked for, and whatever those things are dependent on, to import
      def set_import_targets
        to_import = option_entities.split(',')
        DirCommand.known.each_key do |key|
          DirCommand.known[key]['import'] = (to_import.include?(key) or to_import.include?('all'))
          depends_on = DirCommand.known[key]['depends-on'].split(',')
          depends_on.each do |entity_name|
            DirCommand.known[entity_name]['import'] = true
          end
        end
      end

      # Do the import(s)
      def import_from
        DirCommand.entity_order.each do |key|
          a_map = DirCommand.known[key]
          import_file = "#{option_directory}/#{a_map['export-file']}.csv"
          if a_map['import']
            puts "IMPORT #{key} FROM #{import_file}"
            args = ['--csv-file', import_file]

            #############################################################
            # MAGIC! We create a class from the class-name-string here! #
            #############################################################
            import_class = HammerCLIImport::ImportCommand.const_get(a_map['import-class'])
            unless option_dry_run?
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
