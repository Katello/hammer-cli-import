# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'

module HammerCLIImport
  class ImportCommand
    class UserImportCommand < BaseCommand
      command_name 'user'
      desc 'Import users.'

      option ['--new-passwords'], 'FILE_NAME', 'Output for new passwords', :required => true

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
        CSVHelper.csv_write_hashes(option_new_passwords, [:mail, :login, :password], @new_passwords)
      end

      def import_single_row(data)
        user = mk_user_hash data
        create_entity(:users, user, data['user_id'].to_i)

        @new_passwords ||= []
        @new_passwords << {:login => user[:login], :password => user[:password], :mail => user[:mail]}
      end

      def delete_single_row(data)
        delete_entity(:users, data['user_id'].to_i)
      end
    end
  end
end
