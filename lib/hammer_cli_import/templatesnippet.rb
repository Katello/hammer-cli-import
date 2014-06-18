# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'
require 'apipie-bindings'

module HammerCLIImport
  class ImportCommand
    class TemplateSnippetImportCommand < BaseCommand
      command_name 'template-snippet'
      desc 'Import template snippets.'

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
