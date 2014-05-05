module HammerCLIImport
  class ImportCommand
    class CustomChannelImportCommand < BaseCommand
      command_name 'custom-channel'
      desc 'Import custom channels.'

      csv_columns 'org_id', 'id', 'channel_label', 'name', 'summary', \
                  'description', 'parent_channel_label', 'channel_arch', \
                  'checksum_type', 'associated_repo_id_label'

      persistent_maps :organizations, :repositories, :content_views

      def mk_content_view_hash(data)
        {
          :name => data['name'],
          :description => data['description'],
          :organization_id => lookup_entity(:organizations, get_translated_id(:organizations, data['org_id'].to_i))['label'],
          :repository_ids  => (data['associated_repo_id_label'] || '').split(';').collect do |repo_id_label|
            repo_id, _repo_label = repo_id_label.split('|', 2)
            get_translated_id :repositories, repo_id.to_i
          end
        }
      end

      def import_single_row(data)
        content_view = mk_content_view_hash data
        create_entity(:content_views, content_view, data['id'].to_i)
      end
    end
  end
end
