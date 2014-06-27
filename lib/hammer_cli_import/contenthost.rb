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

module HammerCLIImport
  class ImportCommand
    class ContentHostImportCommand < BaseCommand
      command_name 'content-host'
      desc 'Import content hosts.'

      csv_columns 'server_id', 'profile_name', 'hostname', 'description',
                  'organization_id', 'architecture', 'release',
                  'base_channel_id', 'child_channel_id', 'system_group_id'

      persistent_maps :organizations, :content_views, :host_collections, :systems

      def mk_profile_hash(data)
        {
          :name => data['profile_name'],
          :description => "#{data['description']}\nsat5_system_id: #{data['server_id']}",
          :facts => {'release' => data['release'], 'architecture' => data['architecture']},
          :type => 'content host',
          :cp_type => 'content host',
          # :guest_ids => [],
          :organization_id => data['organization_id'].to_i,
          # :content_view_id => nil,
          :host_colletion_id => data['system_group_id']
        }
      end

      def import_single_row(data)
        profile = mk_profile_hash data
        create_entity(:systems, profile, data['server_id'].to_i)
      end

      def delete_single_row(data)
        profile_id = data['system_id'].to_i
        unless @pm[:systems][profile_id]
          puts "#{to_singular(:systems).capitalize} with id #{profile_id} wasn't imported. Skipping deletion."
          return
        end
        delete_entity(:systems, profile_id)
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
