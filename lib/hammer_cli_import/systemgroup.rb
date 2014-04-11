# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'
require 'apipie-bindings'

module HammerCLIImport
  class Sat5Command
    class SystemGroupImportCommand < BaseCommand

      command_name "system-group"
      desc "Import system groups"

      persistent_maps :system_groups

      def mk_sg_hash(data)
          {
            :name => data["name"],
            :organization_id => lookup_entity(:organizations, get_translated_id(:organizations, data["org_id"]))["label"],
          }
      end

      def import_single_row(data)
        sg = mk_sg_hash data
        create_entity(:system_groups, sg, data["group_id"])
      end
    end
    autoload_subcommands
  end
end
