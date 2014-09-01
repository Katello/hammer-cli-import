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

require 'set'

module HammerCLIImport
  class ImportCommand
    class LocalRepositoryImportCommand < BaseCommand
      extend ImportTools::Repository::Extend
      include ImportTools::Repository::Include
      include ImportTools::ContentView::Include

      command_name 'content-view'
      desc 'Create Content Views based on local/cloned Channels (from spacewalk-export-channels).'

      csv_columns 'org_id', 'channel_id', 'channel_label', 'channel_name'

      persistent_maps :organizations, :repositories, :local_repositories, :content_views,
                      :products, :redhat_repositories, :redhat_content_views, :system_content_views

      option ['--dir'], 'DIR', 'Export directory'
      option ['--filter'], :flag, 'Filter content-views for package names present in Sat5 channel', :default => false
      add_repo_options

      def directory
        File.expand_path(option_dir || File.dirname(option_csv_file))
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
          repo['last_sync'].nil? || last < Time.parse(repo['last_sync'])
        end
      end

      def push_unless_nil(col, obj)
        col << obj unless obj.nil?
      end

      def load_custom_channel_info(org_id, channel_id)
        headers = %w(org_id channel_id package_nevra package_rpm_name in_repo in_parent_channel)
        file = File.join directory, org_id.to_s, channel_id.to_s + '.csv'

        packages_in_channel = Set[]
        repo_ids = Set[]
        parent_channel_ids = Set[]
        has_local_packages = false

        CSVHelper.csv_each file, headers do |data|
          packages_in_channel << data['package_nevra']
          push_unless_nil parent_channel_ids, data['in_parent_channel']
          push_unless_nil repo_ids, data['in_repo']
          has_local_packages ||= data['in_repo'].nil? && data['in_parent_channel'].nil?
        end

        raise "Multiple parents for channel #{channel_id}?" unless parent_channel_ids.size.between? 0, 1

        [repo_ids.to_a, parent_channel_ids.to_a, packages_in_channel.to_a, has_local_packages]
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
        org_id = data['org_id'].to_i

        repo_ids, clone_parents, packages, has_local = load_custom_channel_info org_id, data['channel_id'].to_i

        repo_ids.map! { |id| get_translated_id :repositories, id.to_i }

        if has_local
          local_repo = add_local_repo data
          sync_repo local_repo unless repo_synced? local_repo
          repo_ids.push local_repo['id'].to_i
        end

        clone_parents.collect { |x| Integer(x) } .each do |parent_id|
          begin
            begin
              parent_cv = get_cache(:redhat_content_views)[get_translated_id :redhat_content_views, [org_id, parent_id]]
            rescue
              parent_cv = get_cache(:content_views)[get_translated_id :content_views, parent_id]
            end
            repo_ids += parent_cv['repositories'].collect { |x| x['id'] }
          rescue HammerCLIImport::MissingObjectError
            error "No such {redhat_,}content_view: #{parent_id}"
          end
        end

        repo_ids.collect { |id| lookup_entity :repositories, id } .each do |repo|
          unless repo_synced? repo
            warn "Repository #{repo['label']} is not (fully) synchronized. Retry once synchronization has completed."
            report_summary :skipped, :content_views
            return
          end
        end
        content_view = mk_content_view_hash data, repo_ids

        cw = create_entity :content_views, content_view, data['channel_id'].to_i
        add_repo_filters cw['id'], packages if option_filter?
        publish_content_view cw['id'] if newer_repositories cw
      end

      def delete_single_row(data)
        cv_id = data['channel_id'].to_i
        unless @pm[:content_views][cv_id] || @pm[:redhat_content_views][cv_id] || @pm[:system_content_views][cv_id]
          info "#{to_singular(:systems).capitalize} with id #{cv_id} wasn't imported. Skipping deletion."
          return
        end
        translated = get_translated_id :content_views, cv_id

        # delete_entity :content_views, cv_id
        delete_content_view translated
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
