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
require 'json'

module HammerCLIImport
  class ImportCommand
    class RepositoryEnableCommand < BaseCommand
      extend ImportTools::Repository::Extend
      include ImportTools::Repository::Include
      include ImportTools::ContentView::Include

      command_name 'repository-enable'
      desc 'Enable any Red Hat repositories accessible to any Organization'

      option ['--repository-map'],
             'FILE_NAME',
             'JSON file mapping channel-labels to repository information',
             :default => File.expand_path('../../channel_data_pretty.json', File.dirname(__FILE__))

      option ['--dry-run'],
             :flag,
             'Only show the repositories that would be enabled',
             :default => false

      add_repo_options

      # Required or BaseCommand gets angry at you
      csv_columns 'channel_label', 'channel_name', 'number_of_packages', 'org_id'
      persistent_maps :organizations, :products,
                      :redhat_repositories, :redhat_content_views, :repositories

      # BaseCommand will read our channel-csv for us
      def import_single_row(row)
        handle_row(row, true)
      end

      def delete_single_row(row)
        handle_row(row, false)
      end

      def handle_row(row, enable)
        if row['org_id']
          puts " Skipping #{row['channel_label']} in organization #{row['org_id']}"
          return
        end

        # read_channel_mapping_data will be called only once per subcommand
        @channel_to_repo ||= read_channel_mapping_data(option_repository_map)
        channel_label = row['channel_label']
        repo_set_info = @channel_to_repo[channel_label]

        # rely on we see only products in imported organizations
        get_cache(:products).each do |product_id, product|
          product['product_content'].each do |rs|
            rs_id = rs['content']['id']
            rs_url = rs['content']['contentUrl']

            next if repo_set_info['set-url'] != rs_url

            product_org = lookup_entity_in_cache(:organizations, {'label' => product['organization']['label']})
            if enable
              # Turn on the specific repository
              rh_repo = enable_repos(product_org, product_id, rs_id, repo_set_info, channel_label)
              next if rh_repo.nil? || option_dry_run?

              # Finally, if requested, kick off a sync
              uuid = sync_repo rh_repo if option_synchronize? unless repo_synced? rh_repo
              cont_with_cvs = repo_synced?(rh_repo) || option_wait?
              postpone_till([uuid].compact) do
                cv = create_entity(
                  :redhat_content_views,
                  {
                    :organization_id => product_org['id'],
                    :name => row['channel_name'],
                    :description => 'Red Hat channel migrated from Satellite 5',
                    :repository_ids  => [rh_repo['id']]
                  },
                  [product_org['id'], row['channel_label']]
                  )
                publish_content_view(cv['id'])
              end if cont_with_cvs
            else
              disable_repos(product_org, product_id, rs_id, repo_set_info, channel_label)
            end
          end
        end
      end

      # Hydrate the channel-to-repository-data mapping struct
      def read_channel_mapping_data(filename)
        channel_map = {}
        abort("Channel-to-repository-map file #{filename} not found - aborting...") unless File.exist? filename

        File.open(filename, 'r') do |f|
          json = f.read
          channel_map = JSON.parse(json)
        end
        return channel_map
      end

      # Given a repository-set and a channel-to-repo info for that channel,
      # enable the correct repository
      # TODO: persist the resulting repo-id so we don't have to look it up later
      def enable_repos(org, prod_id, repo_set_id, info, c)
        repo = lookup_entity_in_cache(
          :redhat_repositories,
          {
            'content_id' => repo_set_id,
            'organization' => {'label' => org['label']}
          })
        if repo
          puts "Repository #{repo['url']} already enabled as #{repo['id']}"
          return repo
        end
        puts "Enabling #{info['url']} for channel #{c} in org #{org['id']}"
        begin
          unless option_dry_run?
            rc = api_call(
              :repository_sets,
              :enable,
              'product_id' => prod_id,
              'id' => repo_set_id,
              'basearch' => info['arch'],
              'releasever' => info['version'])

            original_org_id = get_original_id(:organizations, org['id'])
            map_entity(:redhat_repositories, [original_org_id, c], rc['input']['repository']['id'])
            # store to cache (using lookup_entity, because :redhat_repositories api
            # does not return full repository hash)
            return lookup_entity(:redhat_repositories, rc['input']['repository']['id'], true)
          end
        rescue RestClient::Exception  => e
          if e.http_code == 409
            puts '...already enabled.'
          else
            puts "...unknown error #{e.http_code}, #{e.message} - skipping."
          end
        end
      end

      def disable_repos(org, prod_id, repo_set_id, info, c)
        repo = lookup_entity_in_cache(
          :redhat_repositories,
          {
            'content_id' => repo_set_id,
            'organization' => {'label' => org['label']}
          })
        unless repo
          puts "Unknown repository (#{c} equivalent) to disable."
          return
        end
        puts "Disabling #{info['url']} for channel #{c} in org #{org['id']}"
        begin
          unless option_dry_run?
            rc = api_call(
              :repository_sets,
              :disable,
              'product_id' => prod_id,
              'id' => repo_set_id,
              'basearch' => info['arch'],
              'releasever' => info['version'])

            unmap_entity(:redhat_repositories, rc['input']['repository']['id'])
            get_cache(:redhat_repositories).delete(rc['input']['repository']['id'])
            return rc['input']['repository']
          end
        rescue RestClient::Exception  => e
          if e.http_code == 404
            puts '...no such repository to disable.'
          else
            puts "...unknown error #{e.http_code}, #{e.message} - skipping."
          end
        end
      end

      def post_import(_file)
        HammerCLI::EX_OK
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
