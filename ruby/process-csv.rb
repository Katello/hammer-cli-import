#!/usr/bin/env ruby

# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby

require 'csv'
require 'set'

# CSV.foreach("kwak",{:headers => :first_row, :return_headers => false}) do |row|

class Users
  def initialize
    @orgs = Set.new
  end

  def create_user(row)
    username = row['username']
    password = username + '_' + (0...8).map { ('a'..'z').to_a[rand(26)] }.join
    print "Creating user ", row['username'], ' with password ', password
    # p row
    print "\n"
  end

  def create_org(org_name)
    print "Creating org ", org_name, "\n"
    @orgs << org_name
  end

  def import(filename)
    reader = CSV.open(filename, "r")
    header = reader.shift

    reader.each do |row|
      user = Hash[header.zip row]
      org_name = user["organization"]
      create_org org_name unless @orgs.include? org_name
      create_user user
    end

  end
end

instance = Users.new
instance.import("example-export-users.csv")
