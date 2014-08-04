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
require 'set'
require 'socket'

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

      option ['--export-directory'], 'DIR_PATH', 'Directory to export rpmbuild structure'

      validate_options do
        any(:option_export_directory, :option_delete).required
      end

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
        # store processed system profiles to a set according to the organization
        @map ||= Set.new
        @map << {
          :org_id => data['organization_id'].to_i,
          :system_id => data['server_id'].to_i,
          :uuid => c_host['uuid']}
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
        # create rpmbuild directories
        create_rpmbuild_structure
        # create mapping files
        org_ids = @map.collect { |dict| dict[:org_id] }.sort.uniq
        org_ids.each do |org_id|
          version = '0.0.1'
          rpm_name = "system-profile-migrate-#{Socket.gethostname}-org#{org_id}"
          tar_name = "#{rpm_name}-#{version}"
          dir_name = File.join(option_export_directory, tar_name)
          # create SOURCES id_to_uuid.map file
          FileUtils.rm_rf(dir_name) if File.directory?(dir_name)
          Dir.mkdir dir_name
          CSVHelper.csv_write_hashes(
            File.join(dir_name, 'system-id_to_uuid.map'),
            [:system_id, :uuid],
            @map.select { |dict| dict[:org_id] == org_id })

          sources_dir = File.join(option_export_directory, 'SOURCES')
          # debug("tar -C #{option_export_directory} -czf #{sources_dir}/#{tar_name}.tar.gz #{tar_name}")
          system("tar -C #{option_export_directory} -czf #{sources_dir}/#{tar_name}.tar.gz #{tar_name}")
          FileUtils.rm_rf(dir_name)
          # store spec file
          File.open(
            File.join(option_export_directory, 'SPECS', "#{tar_name}.spec"), 'w') do |file|
            file.write(rpm_spec(rpm_name, version, DateTime.now.strftime('%a %b %e %Y')
))
          end
        end
        progress ''
        progress 'To build the system-profile-migrate rpms, run:'
        progress ''
        progress "\tcd #{option_export_directory}/SPECS && for spec in $(ls *.spec)"
        progress "\t  do rpmbuild -ba --define \"_topdir #{option_export_directory}\" $spec"
        progress "\tdone"
        progress ''
        progress "Then find your rpms in #{File.join(option_export_directory, 'RPMS/noarch/')} directory."
      end

      def delete_single_row(data)
        profile_id = data['server_id'].to_i
        unless @pm[:systems][profile_id]
          info "#{to_singular(:systems).capitalize} with id #{profile_id} wasn't imported. Skipping deletion."
          return
        end
        delete_entity_by_import_id(:systems, get_translated_id(:systems, profile_id), 'uuid')
      end

      def _create_dir(dir_name)
        Dir.mkdir(dir_name) unless File.directory?(dir_name)
      end

      def create_rpmbuild_structure
        _create_dir option_export_directory
        _create_dir File.join(option_export_directory, 'SPECS')
        _create_dir File.join(option_export_directory, 'SOURCES')
      end

      def rpm_spec(rpm_name, version, date)
        "
Name:       #{rpm_name}
Version:    #{version}
Release:    1%{?dist}
Summary:    System profile migration tool

Group:      Applications/Productivity
License:    GPLv3
URL:        https://github.com/Katello/hammer-cli-import
Source0:    #{rpm_name}-#{version}.tar.gz
BuildRoot:  %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
BuildArch: noarch

Requires:   subscription-manager-migration

%define  debug_package %{nil}

%description
This tool registeres system profiles managed by Red Hat Satellite 5 to Red Hat Satellite 6 as part of the migration process.

%prep
%setup -q


%build


%install
#mkdir -p $RPM_BUILD_ROOT/%{_datarootdir}/migrate
install -m 755 -d $RPM_BUILD_ROOT/%{_datarootdir}/migrate
install -m 644 system-id_to_uuid.map $RPM_BUILD_ROOT/%{_datarootdir}/migrate/


%post
# run register here

%clean
rm -rf %{buildroot}


%files
%defattr(-,root,root,-)
/usr/share/migrate/system-id_to_uuid.map
%doc


%changelog
* #{date} root <root@localhost> initial package build
- using system profile mapping data for a single organization
"
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
