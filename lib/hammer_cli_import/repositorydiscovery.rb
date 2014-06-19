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
    class RepositoryDiscoveryCommand < BaseCommand
      extend ImportTools::Repository::Extend
      include ImportTools::Repository::Include

      command_name 'repository-discovery'
      desc 'Discover all Repositories accessible to any Organization'

      option ['--repository-map'],
             'FILE_NAME',
             'JSON file mapping channel-labels to repository information',
             :default => File.dirname(__FILE__) + '/../../channel_data_pretty.json'

      option ['--dry-run'],
             :flag,
             'Only show the repositories that would be enabled',
             :default => false

      add_repo_options

      # Required or BaseCommand gets angry at you
      csv_columns 'channel_label', 'channel_name', 'number_of_packages', 'org_id'
      persistent_maps :organizations, :products

      # We provide the output of this process in the distribution of the tool - this code exists
      # only if someone wants to do their own mapping (?!?)
      #
      # Fun heuristics below
      #
      # cdn-map file is JSON, [{'channel'=>c, 'path'=>p},...]
      # In 'path', if we can find the 'basearch', we can (usually) derive the
      # right 'releasever' - path-fmt is .../$releasever/$basearch...'
      # solaris breaks things - skip it
      # fasttrack has no $releasever
      # repo-set-urls don't end in /Package
      #
      # Return a map keyed by channel-label, returns map of
      #   {url, version, arch, set-url}
      # We should be able to match set-url to repo-set['url']
      # Fun!
      def read_channel_map(filename)
        rc = {}
        parsed = ''
        File.open(filename, 'r') do |f|
          json = f.read
          # [ {'channel', 'path'}...]
          parsed = JSON.parse(json)
        end

        archs = %w(i386 x86_64 s390x s390 ppc64 ppc ia64)
        parsed.each do |c|
          path_lst = c['path'].split('/')
          arch_ndx = path_lst.index { |a| archs.include?(a) }
          if arch_ndx.nil?
            puts 'Arch not found: [' + c['path'] + '], skipping...'
            next
          end
          vers_ndx = arch_ndx - 1
          channel_data = {
            'url' => c['path'],
            'version' => path_lst[vers_ndx],
            'arch' => path_lst[arch_ndx]
          }
          path_lst[arch_ndx] = '$basearch'
          path_lst[vers_ndx] = '$releasever' unless path_lst[1] == 'fastrack'
          repo_set_url = path_lst[0..-2].join('/')
          channel_data['set-url'] = repo_set_url
          rc[c['channel']] = channel_data
        end

        return rc
      end

      def initialize(*list)
        super(*list)
        @channels = []
      end

      # BaseCommand will read our channel-csv for us
      def import_single_row(row)
        @channels << row['channel_label'] if row['org_id'].nil?
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

      # Construct reverse-map {set-url {channel-label}, ...}
      def construct_repo_map(channel_map, channels)
        repo_map = {}
        channels.each do |c|
          repo = channel_map[c]
          next if repo.nil?

          repo_map[repo['set-url']] = c
        end
        return repo_map
      end

      # Given a repository-set and a channel-to-repo info for that channel,
      # enable the correct repository
      # TODO: persist the resulting repo-id so we don't have to look it up later
      def enable_repos(org_id, prod_id, repo_set_id, info, c)
        puts "Enabling #{info['url']} for channel #{c}"
        begin
          unless option_dry_run?
            rc = api_call(
              :repository_sets,
              :enable,
              'organization_id' => org_id,
              'product_id' => prod_id,
              'id' => repo_set_id,
              'basearch' => info['arch'],
              'releasever' => info['version'])

            return rc['input']['repository']
          end
        rescue RestClient::Exception  => e
          throw e unless e.http_code == 409
          puts '...already enabled.'
        end
      end

      def post_import(_file)
        # Set up/hydrate our data structures
        channel_to_repo = read_channel_mapping_data(option_repository_map)
        repo_to_channel = construct_repo_map(channel_to_repo, @channels)

        get_cache(:organizations).each do |oid, org|
          get_cache(:products).each do |pid, prod|
            next unless org['label'] == prod['organization']['label']

            prod['product_content'].each do |rs|
              rs_id = rs['content']['id']
              rs_url = rs['content']['contentUrl']
              # Do we care about a channel that matches this repo-set?
              matching_channel = repo_to_channel[rs_url]
              next if matching_channel.nil?

              # Get the repo-set-info that applies to that channel
              repo_set_info = channel_to_repo[matching_channel]
              next if repo_set_info.nil?

              # Turn on the specific repository
              enabled_repo = enable_repos(oid, pid, rs_id, repo_set_info, matching_channel)
              next if enabled_repo.nil? || option_dry_run?

              # Finally, if requested, kick off a sync
              sync_repo enabled_repo
            end
          end
        end

        HammerCLI::EX_OK
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
