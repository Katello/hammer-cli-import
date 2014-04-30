# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'

module HammerCLIImport
  class ImportCommand
    class OrganizationImportCommand < BaseCommand

      command_name 'organization'
      desc 'Import organizations.'

      csv_columns 'organization_id', 'organization'

      persistent_maps :organizations

      def mk_org_hash(data)
        {
          :id => data['organization_id'].to_i,
          :name => data['organization'],
          :description => "Imported '#{data['organization']}' organization from Red Hat Satellite 5"
        }
      end

      def import_single_row(data)
        org = mk_org_hash data
        create_entity(:organizations, org, data['organization_id'].to_i)
      end

      def delete_single_row(data)
        delete_entity(:organizations, data['organization_id'].to_i)
      end

    end
  end
end
