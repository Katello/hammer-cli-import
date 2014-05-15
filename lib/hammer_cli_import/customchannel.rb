module HammerCLIImport
  class ImportCommand
    class CustomChannelImportCommand < BaseCommand
      # command_name 'custom-channel'
      # desc 'Import custom channels.'

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

      def publish_content_view(id)
        puts "Publishing content view with id=#{id}"
        @api.resource(:content_views).call(:publish, {:id => id})
      end

      def newer_repositories(cw)
        last = cw['last_published']
        return true unless last
        last = Time.parse(last)
        cw['repositories'].any? do |repo|
          last < Time.parse(repo['last_sync'])
        end
      end

      def import_single_row(data)
        content_view = mk_content_view_hash data
        content_view[:repository_ids].collect { |id| lookup_entity :repositories, id } .each do |repo|
          unless repo['sync_state'] == 'finished'
            puts "Repository #{repo['label']} is currently synchronizing. Retry once it has completed."
            return
          end
        end
        cw = create_entity(:content_views, content_view, data['id'].to_i)
        publish_content_view cw['id'] if newer_repositories cw
      end
    end
  end
end
