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
require 'yaml'

module HammerCLIImport
  class ImportCommand
    class UserImportCommand < BaseCommand
      command_name 'user'
      reportname = 'users'
      desc "Import Users (from spacewalk-report #{reportname})."

      option ['--new-passwords'], 'FILE_NAME', 'Output for new passwords' do |filename|
        raise ArgumentError, "File #{filename} already exists" if File.exist? filename
        filename
      end

      option ['--merge-users'], :flag, 'Merge pre-created users (except admin)', :default => false

      option ['--role-mapping'], 'FILE_NAME',
             'Mapping of Satellite-5 role names to Satellite-6 defined roles',
             :default => '/etc/hammer/cli.modules.d/import/role_map.yml'

      validate_options do
        any(:option_new_passwords, :option_delete).required
      end

      csv_columns 'organization_id', 'user_id', 'username',\
                  'last_name', 'first_name', 'email', 'role', 'active'

      persistent_maps :organizations, :users

      # Override so we can read the role-map *once*, not *once per user*
      def first_time_only
        if File.exist? option_role_mapping
          @role_map = YAML.load_file(option_role_mapping)
        else
          warn "Role-mapping file #{option_role_mapping} not found, no roles will be assigned"
        end
        return 'loaded'
      end

      def genpw(username)
        username + '_' + (0...8).collect { ('a'..'z').to_a[rand(26)] }.join
      end

      # Admin-flag should be set if any Sat5-role has '_admin_' in its map
      def admin?(data)
        return false if @role_map.nil?

        roles = split_multival(data['role'], false)
        is_admin = false
        roles.each do |r|
          is_admin ||= (@role_map[r.gsub(' ', '-')].include? '_admin_')
        end
        return is_admin
      end

      # Return list-of-role-ids that match any sat5-role associated with this user
      # XXX: Role-api doesn't return what it needs to
      # Until BZ 1102816 is fixed, this doesn't work
      # It does serve to show the infrastructure/approach required
      def role_ids_for(data)
        role_list = []
        return role_list if @role_map.nil?

        users_roles = split_multival(data['role'], false)
        fm_roles = api_call(:roles, :index, 'per_page' => 999999)['results']
        debug fm_roles.inspect
        users_roles.each do |s5r|
          fm_roles.each do |fr|
            role_list << fr['id'] if @role_map[s5r.gsub(' ', '-')].include? fr['name']
          end
        end

        return role_list
      end

      def mk_user_hash(data)
        username = data['username']
        username = 'sat5_admin' if username == 'admin'
        {
          :login => username,
          :firstname => data['first_name'],
          :lastname => data['last_name'],
          :mail => data['email'],
          :auth_source_id => 1,
          :password => genpw(username),
          :organization_ids => [get_translated_id(:organizations, data['organization_id'].to_i)],
          :location_ids => [],
          :admin => admin?(data),
          :role_ids => role_ids_for(data)
        }
      end

      def post_import(_)
        return if @new_passwords.nil? || @new_passwords.empty?
        CSVHelper.csv_write_hashes option_new_passwords, [:mail, :login, :password], @new_passwords
      end

      def import_single_row(data)
        @first_time ||= first_time_only
        user = mk_user_hash data
        new_user = true

        user_id = data['user_id'].to_i
        login = user[:login]

        unless @pm[:users][user_id].nil?
          info "User #{login} already imported."
          return
        end

        if option_merge_users?
          existing_user = lookup_entity_in_cache :users, 'login' => user[:login]

          unless existing_user.nil?
            info "User with login #{login} already exists. Associating..."
            map_entity :users, user_id, existing_user['id']
            new_user = false
          end
        end

        return unless new_user

        create_entity :users, user, user_id

        @new_passwords ||= []
        @new_passwords << {:login => user[:login], :password => user[:password], :mail => user[:mail]}
      end

      def delete_single_row(data)
        delete_entity(:users, data['user_id'].to_i)
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
