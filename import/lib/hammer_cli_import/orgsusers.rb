# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'
require 'csv'

module HammerCLIImport
  class UsersOrgsCommand < BaseCommand

    option '--file', 'FILE', _("CSV export") do |filename|
      if @files
        @files << filename
      else
        @files = [filename]
      end
    end

    def genpw(username)
      username + '_' + (0...8).map { ('a'..'z').to_a[rand(26)] }.join
    end

    def create_user!(user)
      print "Creating user #{user[:login]}\n"
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

        :organization_ids => [@orgsmap[data["organization_id"].to_i]],
        :location_ids => [],
        :role_ids => [],
      }
    end

    def create_org!(org)
      print "Creating org #{org[:name]}\n"
      new = @api.resource(:organizations).call(:create, org)
      @imported_orgs[org[:id]] = org
      @orgsmap[org[:id]] = new["organization"]["id"]
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

    def import(filename)
      reader = CSV.open(filename, 'r')
      header = reader.shift

      reader.each do |row|
        data = Hash[header.zip row]
        org = mk_org_hash data
        create_org! org unless @imported_orgs.include? org[:id]
        user = mk_user_hash data
        create_user! user
      end
    end

    def load_map(map_sym)
      {}
    end

    def save_map(map_sym, map)
      nil
    end

    def run_command
      @imported_orgs = {}

      @orgsmap = load_map(:organizations)
      @usersmap = load_map(:users)

      @files.each do |filename|
        import(filename)
      end

      save_map(:users, @usersmap)
      save_map(:organizations, @orgsmap)

      HammerCLI::EX_OK
    end
  end
end

HammerCLI::MainCommand.subcommand("zzz:orgsusers", "Import orgs and users", HammerCLIImport::UsersOrgsCommand)
