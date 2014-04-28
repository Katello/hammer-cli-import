module HammerCLIImport
  class ImportCommand
    class CustomChannelImportCommand < BaseCommand

      command_name "custom-channel"
      desc "Import custom channels."

      csv_columns 'org_id', 'id', 'channel_label', 'name', 'summary', \
                  'description', 'parent_channel_label', 'channel_arch', \
                  'checksum_type', 'associated_repo_label'

      persistent_maps :organizations, :repositories

      def mk_content_view_hash(data)
        {
          :name => data['name'],
          :description => data['description'],
          :organization_id => lookup_entity(:organizations, get_translated_id(:organizations, data['org_id'].to_i))['label'],
          :repository_ids  => data['associated_repo_label'].split(';').map do |repo_label|
            magic(repo_label)
          end
        }
      end

      def import_single_row(data)
        @x ||= 0
        return nil if @x >= 1
        @x += 1

        content_view = mk_content_view_hash
        p content_view
        # create_entity(:content_views, content_views, data['id'].to_i)
      end
    end
  end
end
