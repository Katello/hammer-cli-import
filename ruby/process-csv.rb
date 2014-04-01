#!/usr/bin/env ruby
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby

require 'csv'
# require 'set'
# require 'shellwords'

# CSV.foreach("kwak",{:headers => :first_row, :return_headers => false}) do |row|

class Users
  def initialize
    @imported_orgs = {}
  end

  def shell_escape_utf8(str)
    "\"" + str.gsub(/([\\$"])/, '\\\\\0') + "\""
  end

  def genpw(username)
    username + '_' + (0...8).map { ('a'..'z').to_a[rand(26)] }.join 
  end

  def create_user!(user)
    print "hammer user create" \
      " --login #{shell_escape_utf8 user[:login]}" \
      " --firstname #{shell_escape_utf8 user[:firstname]}" \
      " --lastname #{shell_escape_utf8 user[:lastname]}" \
      " --mail #{shell_escape_utf8 user[:mail]}" \
      " --auth-source-id #{shell_escape_utf8 user[:auth_source_id].to_s}" \
      " --password #{shell_escape_utf8 user[:password]}" \
      "\n"
  end

  def mk_user_hash(data)
    username = data['username']
    {
      :login => username,
      :firstname => data['first_name'],
      :lastname => data['last_name'],
      :mail => data['email'],
      :auth_source_id => 1,
      :password => genpw(username)
    }
  end
 
  def create_org!(org)
    # print "Creating org ", org_name, "\n"
    # label = org_name.downcase
    print "hammer organization create" \
      " --description #{shell_escape_utf8(org[:description])}" \
      " --name #{shell_escape_utf8(org[:name])}" \
      "\n"
      # " --label #{Shellwords.escape(org[:label])}" \
      
    @imported_orgs[org[:id]] = org
  end

  def mk_org_hash(data)
    id = data["organization_id"].to_i
    if @imported_orgs.include? id
      @imported_orgs[id]
    else
      {
        :id => id,
        :name => data["organization"],
        # :label =>  "imported-org-#{id}", # this should be autogenerated if not provided...
        :description => "Organization imported from Satellite 5"
      }
    end
  end
  
  def import(filename)
    reader = CSV.open(filename, "r")
    header = reader.shift
    
    reader.each do |row|
      data = Hash[header.zip row]
      org = mk_org_hash data
      create_org! org unless @imported_orgs.include? org[:id]
      user = mk_user_hash data
      create_user! user
    end
  end
end

instance = Users.new
ARGV.each do |filename|
  instance.import(filename)
end
