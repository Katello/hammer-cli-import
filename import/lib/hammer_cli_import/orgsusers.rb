# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'
require 'csv'

module HammerCLIImport
  class UsersOrgsCommand < BaseCommand

    csv_columns 'organization_id', 'organization', 'user_id', 'username',\
      'last_name', 'first_name', 'email', 'role', 'active'

    persistent_maps :orgs, :users

    def genpw(username)
      username + '_' + (0...8).map { ('a'..'z').to_a[rand(26)] }.join
    end

    def create_user!(user)
      puts "Creating user #{user[:login]}"
      new = @api.resource(:users).call(:create, {:user => user})
      # @usersmap[user....] = new["user"]["id"]
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

        :organization_ids => [@pm_orgs[data["organization_id"].to_i]],
        :location_ids => [],
        :role_ids => [],
      }
    end

    def create_org!(org)
      puts "Creating org #{org[:name]}"
      new = @api.resource(:organizations).call(:create, org)
      @imported_orgs[org[:id]] = org
      @pm_orgs[org[:id]] = new["organization"]["id"]
      nil
    end

    def mk_org_hash(data)
      id = data["organization_id"].to_i
      if @imported_orgs.include? id
        @imported_orgs[id]
      else
        {
          :id => id,
          :name => data["organization"],
          :description => "Organization imported from Satellite 5"
        }
      end
    end

    def import_init()
      @imported_orgs = {}
    end

    def import_single_row(data)
      org = mk_org_hash data
      create_org! org unless @imported_orgs.include? org[:id]
      user = mk_user_hash data
      create_user! user
    end
  end
end

HammerCLI::MainCommand.subcommand("zsg:orgsusers", "Import orgs and users", HammerCLIImport::UsersOrgsCommand)
