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
    class OrganizationImportCommand < BaseCommand
      command_name 'organization'
      desc 'Import Organizations.'

      option ['--into-org-id'], 'ORG_ID', 'Import all organizations into one specified by id' do |x|
        Integer(x)
      end

      # Where do we expect to find manifest-files?
      #  NOTE: we won't upload manifests if we're doing into-org-id - the expectation is that
      #  you have already set up your org
      option ['--upload-manifests-from'],
             'MANIFEST_DIR',
             'Upload manifests found at MANIFEST_DIR/<org_name>.zip to matching organizations'

      csv_columns 'organization_id', 'organization'

      persistent_maps :organizations

      def mk_org_hash(data)
        {
          :id => data['organization_id'].to_i,
          :name => data['organization'],
          :description => "Imported '#{data['organization']}' organization from Red Hat Satellite 5"
        }
      end

      # :subscriptions :upload {:org_id => id, :content => File.new(filename, 'rb')}
      def upload_manifest_for(label, id)
        # Remember labels we've already processed in this run
        @manifests ||= []
        return if @manifests.include? label

        @manifests << label
        filename = option_upload_manifests_from + '/' + label + '.zip'
        unless File.exist? filename
          puts "No manifest #{filename} available."
          return
        end

        puts "Uploading manifest #{filename} to org-id #{id}"
        manifest_file = File.new(filename, 'rb')
        request_headers = {:content_type => 'multipart/form-data', :multipart => true}

        begin
          api_call :subscriptions, :upload, {:organization_id => id, :content => manifest_file}, request_headers
        rescue Exception => e
          puts e.inspect
          raise e
        end
      end

      def import_single_row(data)
        if option_into_org_id
          unless lookup_entity_in_cache(:organizations, {'id' => option_into_org_id})
            puts "Organization [#{option_into_org_id}] not found. Skipping."
            return
          end
          map_entity(:organizations, data['organization_id'].to_i, option_into_org_id)
          return
        end
        org = mk_org_hash data
        new_org = create_entity(:organizations, org, data['organization_id'].to_i)
        upload_manifest_for(new_org['label'], new_org['id']) unless option_upload_manifests_from.nil?
      end

      def delete_single_row(data)
        org_id = data['organization_id'].to_i
        unless @pm[:organizations][org_id]
          puts "#{to_singular(:organizations).capitalize} with id #{org_id} wasn't imported. Skipping deletion."
          return
        end
        target_org_id = get_translated_id(:organizations, org_id)
        if last_in_cache?(:organizations, target_org_id)
          puts "Won't delete last organization [#{target_org_id}]. Unmapping only."
          unmap_entity(:organizations, target_org_id)
          return
        end
        if target_org_id == 1
          puts "Won't delete organization with id [#{target_org_id}]. Unmapping only."
          unmap_entity(:organizations, target_org_id)
          return
        end
        delete_entity(:organizations, org_id)
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
