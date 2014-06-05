# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'
require 'set'

module HammerCLIImport
  class ImportCommand
    class LocalRepositoryImportCommand < BaseCommand
      extend ImportTools::Repository::Extend
      include ImportTools::Repository::Include

      command_name 'content-view'
      desc 'Create content-views based on local/cloned channels.'

      csv_columns 'org_id', 'channel_id', 'channel_label', 'channel_name'

      persistent_maps :organizations, :repositories, :local_repositories, :content_views, :products

      option ['--dir'], 'DIR', 'Export directory'
      add_repo_options

      def directory
        option_dir || File.dirname(option_csv_file)
      end

      def mk_product_hash(data, product_name)
        {
          :name => product_name,
          :organization_id => get_translated_id(:organizations, data['org_id'].to_i)
        }
      end

      def mk_repo_hash(data, product_id)
        {
          :name => "Local repository for #{data['channel_label']}",
          :product_id => product_id,
          :url => 'file://' + File.join(directory, data['org_id'], data['channel_id']),
          :content_type => 'yum'
        }
      end

      def publish_content_view(id)
        api_call :content_views, :publish, {:id => id}
      end

      def mk_content_view_hash(data, repo_ids)
        {
          :name => data['channel_name'],

          :description => 'Channel migrated from Satellite 5',

          :organization_id => get_translated_id(:organizations, data['org_id'].to_i),
          :repository_ids  => repo_ids
        }
      end

      def newer_repositories(cw)
        last = cw['last_published']
        return true unless last
        last = Time.parse(last)
        cw['repositories'].any? do |repo|
          last < Time.parse(repo['last_sync'])
        end
      end

      def load_custom_channel_info(org_id, channel_id)
        headers = %w(org_id channel_id package_nevra package_rpm_name in_repo in_parent_channel)
        file = File.join directory, org_id.to_s, channel_id.to_s + '.csv'

        packages_in_channel = Set[]
        repo_ids = Set[]
        parent_channel_ids = Set[]

        CSVHelper.csv_each file, headers do |data|
          packages_in_channel << data['package_nevra']
          parent_channel_ids << data['in_parent_channel']
          repo_ids << data['in_repo']
        end

        [repo_ids.to_a, parent_channel_ids.to_a, packages_in_channel.to_a]
      end

      def add_local_repo(data)
        product_name = 'Local-repositories'
        composite_id = [data['org_id'].to_i, product_name]
        product_hash = mk_product_hash data, product_name
        product_id = create_entity(:products, product_hash, composite_id)['id'].to_i

        repo_hash = mk_repo_hash data, product_id
        local_repo = create_entity :local_repositories, repo_hash, [data['org_id'].to_i, data['channel_id'].to_i]
        local_repo
      end

      # TODO: Move higher into hierarchy?
      def api_call(resource, action, params = {})
        @api.resource(resource).call(action, params)
      rescue
        puts "Error on api.resource(#{resource}).call(#{action}, #{params}):"
        raise
      end

      def add_repo_filters(content_view_id, nevras)
        cw_filter = api_call :content_view_filters,
                             :create,
                             { :content_view_id => content_view_id,
                               :name => 'Satellite 5 channel equivalence filter',
                               :type => 'rpm',
                               :inclusion => true}

        packages = nevras.collect do |package_nevra|
          match = /^([^:]+)-(\d+):([^-]+)-(.*)\.([^.]*)$/.match(package_nevra)
          raise "Bad nevra: #{package_nevra}" unless match

          { :name => match[1],
            :epoch => match[2],
            :version => match[3],
            :release => match[4],
            :architecture => match[5]
          }
        end
        packages.group_by { |package| package[:name] } .each do |name, _packages|
          api_call :content_view_filter_rules,
                   :create,
                   { :content_view_filter_id => cw_filter['id'],
                     :name => name}
        end
      end

      def import_single_row(data)
        local_repo = add_local_repo data
        sync_repo local_repo unless repo_synced? local_repo

        repo_ids, _b, packages = load_custom_channel_info data['org_id'].to_i, data['channel_id'].to_i

        repo_ids.delete nil
        repo_ids.map! { |id| get_translated_id :repositories, id.to_i }
        repo_ids.push local_repo['id'].to_i

        repo_ids.collect { |id| lookup_entity :repositories, id } .each do |repo|
          unless repo_synced? repo
            puts "Repository #{repo['label']} is not (fully) synchronized. Retry once synchronization has completed."
            return
          end
        end
        content_view = mk_content_view_hash data, repo_ids

        cw = create_entity :content_views, content_view, data['channel_id'].to_i
        add_repo_filters cw['id'], packages
        publish_content_view cw['id'] if newer_repositories cw
      end

      def delete_single_row(data)
        cv_id = data['channel_id'].to_i
        translated = get_translated_id :content_views, cv_id

        # delete_entity :content_views, cv_id
        delete_content_view translated
      end

      # TODO: Eliminate duplicity with activation keys
      def delete_content_view(cv_id)
        content_view = get_cache(:content_views)[cv_id]

        cv_versions = content_view['versions'].collect { |v| v['id'] }

        task = api_mapped_resource(:content_views).call(
            :remove,
            {
              :id => content_view['id'],
              :content_view_version_ids => cv_versions
            })

        wait_for_task(task['id'], 1, 0)

        delete_entity_by_import_id(:content_views, content_view['id'])
      end
    end
  end
end
