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
    class TemplateSnippetImportCommand < BaseCommand
      command_name 'template-snippet'
      reportname = 'kickstart-scripts'
      desc "Import template snippets (from spacewalk-report #{reportname})."

      csv_columns \
        'id', 'org_id', 'script_name', 'kickstart_label', 'position',
        'script_type', 'chroot', 'interpreter', 'data'

      persistent_maps :organizations, :template_snippets

      def mk_snippet_hash(data)
        template = "%#{data['script_type']}"
        template += ' --nochroot' if data['chroot'] == 'N'
        template += " --interpreter #{data['interpreter']}" if data['interpreter']
        template += "\n"
        template += data['data']
        template += "\n" unless template.end_with? "\n"
        template += "%end\n"
        {
          :name => "#{data['kickstart_label']}-#{data['org_id']}-" \
          "#{data['position']}-#{data['script_name']}-#{data['script_type']}",
          :template => template,
          # nowadays templates do not get associated with an organization
          # :organization_id => get_translated_id(:organizations, data['org_id'].to_i),
          :snippet => true,
          # audit_comment does not get stored anyway
          :audit_comment => ''
        }
      end

      def import_single_row(data)
        snippet = mk_snippet_hash data
        create_entity(:template_snippets, snippet, data['id'].to_i)
      end

      def delete_single_row(data)
        delete_entity(:template_snippets, data['id'].to_i)
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
