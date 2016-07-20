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
      include ImportTools::ContentView::Include
      include ImportTools::LifecycleEnvironment::Include

      command_name 'content-host'
      reportname = 'system-profiles'
      desc "Import Content Hosts (from spacewalk-report #{reportname})."

      csv_columns 'server_id', 'profile_name', 'hostname', 'description',
                  'organization_id', 'architecture', 'release',
                  'base_channel_id', 'child_channel_id', 'system_group_id',
                  'virtual_host', 'virtual_guest',
                  'base_channel_label'

      persistent_maps :organizations, :content_views, :redhat_content_views, :system_content_views,
                      :host_collections, :hosts

      option ['--export-directory'], 'DIR_PATH', 'Directory to export rpmbuild structure'

      validate_options do
        any(:option_export_directory, :option_delete).required
      end

      def _build_composite_cv_label(data, cvs)
        label = ''
        label += data['base_channel_label'] + '_' if data['base_channel_label']
        label += cvs.sort.join('_')
        label.gsub!(/[^0-9a-z_-]/i, '_')
        return label
      end

      def mk_profile_hash(data, cv_id)
        hcollections = split_multival(data['system_group_id']).collect do |sg_id|
          get_translated_id(:host_collections, sg_id)
        end
        org_id = get_translated_id(:organizations, data['organization_id'].to_i)
        {
          :name => data['profile_name'],
          :comment => "#{data['description']}\nsat5_system_id: #{data['server_id']}",
          :facts => {'release' => data['release'], 'architecture' => data['architecture']},
          # :guest_ids => [],
          :organization_id => org_id,
          :lifecycle_environment_id => get_env(org_id)['id'],
          :content_view_id => cv_id,
          :host_collection_ids => hcollections
        }
      end

      def import_single_row(data)
        @vguests ||= {}
        @map ||= Set.new
        cvs = (split_multival(data['base_channel_id']) + split_multival(data['child_channel_id'])).collect do |channel_id|
          begin
            get_translated_id(:redhat_content_views, [data['organization_id'].to_i, channel_id])
          rescue HammerCLIImport::MissingObjectError
            get_translated_id(:content_views, channel_id)
          end
        end
        cv_id = create_composite_content_view(
          :system_content_views,
          get_translated_id(:organizations, data['organization_id'].to_i),
          _build_composite_cv_label(data, cvs),
          'Composite content view for content hosts',
          cvs)
        profile = mk_profile_hash data, cv_id
        c_host = create_entity(:hosts, profile, data['server_id'].to_i)
        # store processed system profiles to a set according to the organization
        @map << {
          :org_id => data['organization_id'].to_i,
          :system_id => data['server_id'].to_i,
          :host_id => c_host['id'],
          :uuid => c_host['subscription_facet_attributes']['uuid']
        }
        # associate virtual guests in post_import to make sure, all the guests
        # are already imported (and known to sat6)
        @vguests[data['server_id'].to_i] = split_multival(data['virtual_guest']) if data['virtual_host'] == data['server_id']
        debug "vguests: #{@vguests[data['server_id'].to_i].inspect}" if @vguests[data['server_id'].to_i]
      end

      def post_import(_file)
        @vguests.each do |system_id, guest_ids|
          handle_missing_and_supress "setting guests for #{system_id}" do
            uuid = get_translated_id(:hosts, system_id)
            vguest_uuids = guest_ids.collect do |id|
              get_translated_id(:hosts, id)
            end if guest_ids
            debug "Setting virtual guests for #{uuid}: #{vguest_uuids.inspect}"
            update_entity(
              :hosts,
              uuid,
              {:guest_ids => vguest_uuids}
            ) if uuid && vguest_uuids
          end
        end
        return if @map.empty?
        # create rpmbuild directories
        create_rpmbuild_structure
        # create mapping files
        version = '0.0.1'
        now = Time.now
        rpm_name = "system-profile-transition-#{Socket.gethostname}-#{now.to_i}"
        tar_name = "#{rpm_name}-#{version}"
        dir_name = File.join(option_export_directory, tar_name)
        # create SOURCES id_to_uuid.map file
        FileUtils.rm_rf(dir_name) if File.directory?(dir_name)
        Dir.mkdir dir_name
        CSVHelper.csv_write_hashes(
          File.join(dir_name, "system-id_to_uuid-#{now.to_i}.map"),
          [:system_id, :uuid, :org_id],
          @map.sort_by { |x| [x[:org_id], x[:system_id], x[:uuid]] })

        sources_dir = File.join(option_export_directory, 'SOURCES')
        # debug("tar -C #{option_export_directory} -czf #{sources_dir}/#{tar_name}.tar.gz #{tar_name}")
        system("tar -C #{option_export_directory} -czf #{sources_dir}/#{tar_name}.tar.gz #{tar_name}")
        FileUtils.rm_rf(dir_name)
        # store spec file
        File.open(
          File.join(option_export_directory, 'SPECS', "#{tar_name}.spec"), 'w') do |file|
          file.write(rpm_spec(rpm_name, version, now))
        end
        abs_export_directory = File.expand_path(option_export_directory)
        progress ''
        progress 'To build the system-profile-transition rpm, run:'
        progress ''
        progress "\tcd #{abs_export_directory}/SPECS && "
        progress "\t  rpmbuild -ba --define \"_topdir #{abs_export_directory}\" #{tar_name}.spec"
        progress ''
        progress "Then find your #{rpm_name} package"
        progress "\tin #{File.join(abs_export_directory, 'RPMS/noarch/')} directory."
      end

      def delete_single_row(data)
        @composite_cvs ||= Set.new
        profile_id = data['server_id'].to_i
        unless @pm[:hosts][profile_id]
          info "#{to_singular(:hosts).capitalize} with id #{profile_id} wasn't imported. Skipping deletion."
          return
        end
        profile = get_cache(:hosts)[@pm[:hosts][profile_id]]
        cv = get_cache(:content_views)[profile['content_view_id']]
        @composite_cvs << cv['id'] if cv && cv['composite']
        delete_entity_by_import_id(:hosts, get_translated_id(:hosts, profile_id), 'id')
      end

      def post_delete(_file)
        # let's 'try' to delete the system content views
        # there's no chance to find out, whether some other content hosts are associated with them
        @composite_cvs.each do |cv_id|
          silently do
            delete_content_view(cv_id, :system_content_views)
          end
        end
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
Release:    1
Summary:    System profile transition data

Group:      Applications/Productivity
License:    GPLv3
URL:        https://github.com/Katello/hammer-cli-import
Source0:    #{rpm_name}-#{version}.tar.gz
BuildRoot:  %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
BuildArch: noarch

%define _binary_filedigest_algorithm 1
%define _binary_payload w9.gzdio

%define  debug_package %{nil}

%description
This package contains mapping information, how system profiles managed by Red Hat Satellite 5
get translated to content hosts on Red Hat Satellite 6

%prep
%setup -q


%build


%install
install -m 755 -d $RPM_BUILD_ROOT/%{_datarootdir}/rhn/transition
install -m 644 system-id_to_uuid-#{date.to_i}.map $RPM_BUILD_ROOT/%{_datarootdir}/rhn/transition/


%post
# run register here

%clean
rm -rf %{buildroot}


%files
%defattr(-,root,root,-)
/usr/share/rhn/transition/
/usr/share/rhn/transition/system-id_to_uuid-#{date.to_i}.map
%doc


%changelog
* #{date.strftime('%a %b %e %Y')} root <root@localhost> initial package build
- using system profile to content host mapping data
"
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
