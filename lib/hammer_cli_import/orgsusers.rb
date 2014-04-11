# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'
require 'csv'

module HammerCLIImport
  class ImportCommand
    class UsersOrgsCommand < BaseCommand

      command_name "orgsusers"
      desc "Import orgs and users"

      csv_columns 'organization_id', 'organization', 'user_id', 'username',\
        'last_name', 'first_name', 'email', 'role', 'active'

      persistent_maps :organizations, :users

      def genpw(username)
        username + '_' + (0...8).map { ('a'..'z').to_a[rand(26)] }.join
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
          :organization_ids => [@pm[:organizations][data["organization_id"].to_i]],
          :location_ids => [],
          :role_ids => [],
        }
      end

      def mk_org_hash(data)
        {
          :id => data["organization_id"].to_i,
          :name => data["organization"],
          :description => "Imported '#{data["organization"]}' organization from Red Hat Satellite 5"
        }
      end

      def import_single_row(data)
        org = mk_org_hash data
        create_entity(:organizations, org, data["organization_id"])
        user = mk_user_hash data
        create_entity(:users, user, data["user_id"])
      end
    end
  end
end
