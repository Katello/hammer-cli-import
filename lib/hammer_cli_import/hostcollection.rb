#
# Copyright (c) 2014 Red Hat Inc.
#
# This file is part of hammer-cli-import.
#
# hammer-cli-import is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# hammer-cli-import is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with hammer-cli-import.  If not, see <http://www.gnu.org/licenses/>.
#

require 'hammer_cli'
require 'apipie-bindings'

module HammerCLIImport
  class ImportCommand
    class SystemGroupImportCommand < BaseCommand
      command_name 'host-collection'
      desc 'Import Host Collections.'

      csv_columns 'group_id', 'name', 'org_id'

      persistent_maps :organizations, :host_collections

      def mk_sg_hash(data)
        {
          :name => data['name'],
          :organization_id => get_translated_id(:organizations, data['org_id'].to_i)
        }
      end

      def import_single_row(data)
        sg = mk_sg_hash data
        create_entity(:host_collections, sg, data['group_id'].to_i)
      end

      def delete_single_row(data)
        delete_entity(:host_collections, data['group_id'].to_i)
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
