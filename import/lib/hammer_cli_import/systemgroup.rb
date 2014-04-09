# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'
require 'apipie-bindings'

module HammerCLIImport
  class Sat5Command
    class SystemGroupImportCommand < HammerCLI::Apipie::Command

      command_name "sg_import"
      desc "Import system groups command"

      @@translate = {
        "name" => "name",
      }

      option %w(--csv-file), 'FILE_NAME', 'CSV file'

      def translate_dict(dict)
        hash = Hash.new
        @@translate.keys.each do | key |
          hash[@@translate[key]] = dict[key]
        end
        return hash
      end

      def csv_to_dict(csv_file)
        csv = {}
        puts "Reading: #{csv_file}"
        CSV.foreach(csv_file || '/dev/stdin',
          :headers => true, :converters => :all) do |row|
          csv[row.fields[0]] = Hash[row.headers.zip(row.fields)]
        end
        return csv
      end

      def get_org_label(id)
        org = @api.resource(:organizations).call(:show, {"id" => id})
        puts "Translating organization id to label ..."
        return org["label"]
      end

      def execute
        @api = ApipieBindings::API.new({
          :uri => HammerCLI::Settings.get(:foreman, :host),
          :username => HammerCLI::Settings.get(:foreman, :username),
          :password => HammerCLI::Settings.get(:foreman, :password),
          :api_version => 2
        })

        sgs = csv_to_dict(option_csv_file)
        sgs.each do | id, sg |
          begin
            exists = @api.resource(:system_groups).call(:show, {"id" => id})
          # rescue ResourceNotFound
          rescue => e
            #puts "exception"
            #puts e.message
          end
          # puts "exists: #{exists != nil}"
          if exists == nil
            params = translate_dict(sg)
            puts params.inspect
            params["organization_id"] = get_org_label(sg["org_id"])
            new_sg = @api.resource(:system_groups).call(:create, params)
            puts "Creating: #{new_sg.inspect}"
          end
        end

        HammerCLI::EX_OK
      end
    end

    class SystemGroupDeleteCommand < HammerCLI::Apipie::Command

      command_name "sg_remove"
      desc "Delete system groups command"

      option %w(--id), 'ID', 'system group id'

      def execute
        puts "#{option_id}"
        @api = ApipieBindings::API.new({
          :uri => HammerCLI::Settings.get(:foreman, :host),
          :username => HammerCLI::Settings.get(:foreman, :username),
          :password => HammerCLI::Settings.get(:foreman, :password),
          :api_version => 2
        })
        puts @api.resource(:system_groups).call(:destroy, {"id" => option_id})
        HammerCLI::EX_OK
      end
    end
    autoload_subcommands
  end
end
