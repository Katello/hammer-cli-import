# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'
require 'yaml'

module HammerCLIImport
  class ImportCommand
    class UserImportCommand < BaseCommand
      command_name 'user'
      desc 'Import users.'

      option ['--new-passwords'], 'FILE_NAME', 'Output for new passwords' do |filename|
        raise ArgumentError, "File #{filename} already exists" if File.exist? filename
        filename
      end

      option ['--merge-users'], :flag, 'Merge pre-created users (except admin)', :default => false

      option ['--role-mapping'], 'FILE_NAME', 'Mapping of Satellite-5 role names to Satellite-6 defined roles', :default => '/etc/hammer/cli.modules.d/role_map.yml'

      validate_options do
        any(:option_new_passwords, :option_delete).required
      end

      csv_columns 'organization_id', 'user_id', 'username',\
                  'last_name', 'first_name', 'email', 'role', 'active'

      persistent_maps :organizations, :users

      # Override so we can read the role-map *once*, not *once per user*
      def execute
        if option_role_mapping
          @role_map = YAML.load_file(option_role_mapping)
        end
        super()
      end

      def genpw(username)
        username + '_' + (0...8).collect { ('a'..'z').to_a[rand(26)] }.join
      end

      # Admin-flag should be set if any Sat5-role has '_admin_' in its map
      def admin?(data)
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
        users_roles = split_multival(data['role'], false)
        # Someday, this will work
        #fm_roles = @api.resource(:roles).call(:index, 'per_page' => 999999);
        # Until then - here's some fake data to drive the plumbing
        fm_roles = [{'id' => 1, 'name' => 'foo'},
                    {'id' => 2, 'name' => 'bar'},
                    {'id' => 3, 'name' => 'blech'}]
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
        user = mk_user_hash data
        new_user = true

        user_id = data['user_id'].to_i
        login = user[:login]

        unless @pm[:users][user_id].nil?
          puts "User #{login} already imported."
          return
        end

        if option_merge_users?
          existing_user = lookup_entity_in_cache :users, 'login' => user[:login]

          unless existing_user.nil?
            puts "User with login #{login} already exists. Associating..."
            @pm[:users][user_id] = existing_user['id']
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
