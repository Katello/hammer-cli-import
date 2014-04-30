# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'
require 'apipie-bindings'

module HammerCLIImport
  class ImportCommand
    class SystemGroupImportCommand < BaseCommand
      command_name 'system-group'
      desc 'Import system groups.'

      csv_columns 'group_id', 'name', 'org_id'

      persistent_maps :system_groups, :organizations

      def mk_sg_hash(data)
          {
            :name => data['name'],
            :organization_id => lookup_entity(:organizations, get_translated_id(:organizations, data['org_id']))['label'],
          }
      end

      def import_single_row(data)
        sg = mk_sg_hash data
        create_entity(:system_groups, sg, data['group_id'].to_i)
      end

      def delete_single_row(data)
        delete_entity(:system_groups, data['group_id'].to_i)
      end
    end
  end
end
