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
      reportname = 'system-profiles'
      desc "Import Content Hosts (from spacewalk-report #{reportname})."

      csv_columns 'server_id', 'profile_name', 'hostname', 'description',
                  'organization_id', 'architecture', 'release',
                  'base_channel_id', 'child_channel_id', 'system_group_id',
                  'virtual_host', 'virtual_guest'

      persistent_maps :organizations, :content_views, :host_collections, :systems

      def _translate_system_id_to_uuid(system_id)
        return lookup_entity(:systems, get_translated_id(:systems, system_id))['uuid']
      end

      def mk_profile_hash(data)
        hcollections = split_multival(data['system_group_id']).collect do |sg_id|
          get_translated_id(:host_collections, sg_id)
        end
        {
          :name => data['profile_name'],
          :description => "#{data['description']}\nsat5_system_id: #{data['server_id']}",
          :facts => {'release' => data['release'], 'architecture' => data['architecture']},
          :type => 'system',
          # :guest_ids => [],
          :organization_id => get_translated_id(:organizations, data['organization_id'].to_i),
          # :content_view_id => nil,
          :host_colletion_id => hcollections
        }
      end

      def import_single_row(data)
        @vguests ||= {}
        profile = mk_profile_hash data
        c_host = create_entity(:systems, profile, data['server_id'].to_i)
        # associate virtual guests in post_import to make sure, all the guests
        # are already imported (and known to sat6)
        @vguests[data['server_id'].to_i] = split_multival(data['virtual_guest']) if data['virtual_host'] == data['server_id']
        debug "vguests: #{@vguests[data['server_id'].to_i].inspect}" if @vguests[data['server_id'].to_i]
      end

      def post_import(_file)
        @vguests.each do |system_id, guest_ids|
          uuid = _translate_system_id_to_uuid(system_id)
          vguest_uuids = guest_ids.collect do |id|
            _translate_system_id_to_uuid(id)
          end if guest_ids
          debug "Setting virtual guests for #{uuid}: #{vguest_uuids.inspect}"
          update_entity(
            :systems,
            uuid,
            {:guest_ids => vguest_uuids}
            ) if uuid && vguest_uuids
        end
      end

      def delete_single_row(data)
        profile_id = data['server_id'].to_i
        unless @pm[:systems][profile_id]
          info "#{to_singular(:systems).capitalize} with id #{profile_id} wasn't imported. Skipping deletion."
          return
        end
        delete_entity_by_import_id(:systems, get_translated_id(:systems, profile_id), 'uuid')
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
