# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'

module HammerCLIImport
  class ImportCommand
    class UserImportCommand < BaseCommand
      command_name 'user'
      desc 'Import users.'

      option ['--new-passwords'], 'FILE_NAME', 'Output for new passwords' do |filename|
        raise ArgumentError, "File #{filename} already exists" if File.exist? filename
        filename
      end

      validate_options do
        any(:option_new_passwords, :option_delete).required
      end

      csv_columns 'organization_id', 'user_id', 'username',\
                  'last_name', 'first_name', 'email', 'role', 'active'

      persistent_maps :organizations, :users

      def genpw(username)
        username + '_' + (0...8).collect { ('a'..'z').to_a[rand(26)] }.join
      end

      def mk_user_hash(data)
        username = data['username']
        {
          :login => username,
          :firstname => data['first_name'],
          :lastname => data['last_name'],
          :mail => data['email'],
          :auth_source_id => 1,
          :password => genpw(username),
          :organization_ids => [get_translated_id(:organizations, data['organization_id'].to_i)],
          :location_ids => [],
          :role_ids => []
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

        existing_user = lookup_entity_in_cache :users, 'login' => user[:login]

        unless existing_user.nil?
          puts "User with login #{login} already exists. Associating..."
          @pm[:users][user_id] = existing_user['id']
          new_user = false
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
