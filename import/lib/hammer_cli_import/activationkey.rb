# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'
require 'apipie-bindings'

module HammerCLIImport
  class ImportCommand
    class ActivationKeyImportCommand < BaseCommand
      command_name 'activation-key'
      desc 'Import activation keys.'

      csv_columns 'key_token', 'org_id', 'key_note', 'server_group_id'

      persistent_maps :organizations, :host_collections, :content_views
      persistent_map :activation_keys, ['sat5' => String], ['sat6' => Fixnum]

      def mk_ak_hash(data)
        usage_limit = 'unlimited'
        usage_limit = data['usage_limit'] if data['usage_limit']
        {
          :name => data['key_token'],
          :organization_id => lookup_entity(:organizations, get_translated_id(:organizations, data['org_id']))['label'],
          :label => data['key_token'],
          :description => data['key_note'],
          :usage_limit => usage_limit,
          :content_view_id => get_translated_id(:content_views, data['channel_id'])
        }
      end

      def associate_with_host_collection(ak_id, data)
        @api.resource(:host_collections).call(
          :add_activation_keys,
          {:id => get_translated_id(:host_collections, data['server_group_id']),
           :activation_key_ids => [ak_id]
          })
      end

      def import_single_row(data)
        sg = mk_ak_hash data
        ak = create_entity(:activation_keys, sg, data['key_token'])
        if (data['server_group_id'])
          associate_with_host_collection(ak['id'], data)
        end
      end

      def delete_single_row(data)
        delete_entity(:activation_keys, data['key_token'])
      end
    end
  end
end
