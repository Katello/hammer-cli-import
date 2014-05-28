# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'
require 'apipie-bindings'

module HammerCLIImport
  class ImportCommand
    class ActivationKeyImportCommand < BaseCommand
      command_name 'activation-key'
      desc 'Import activation keys.'

      csv_columns 'token', 'org_id', 'note', 'usage_limit', 'base_channel_id', 'child_channel_id', 'server_group_id'

      persistent_maps :organizations, :host_collections, :ak_content_views, :content_views, :activation_keys

      def mk_ak_hash(data)
        usage_limit = 'unlimited'
        usage_limit = data['usage_limit'].to_i if data['usage_limit']
        puts "  Activation key usage_limit: #{usage_limit}"
        {
          :name => data['token'],
          :organization_id => get_translated_id(:organizations, data['org_id'].to_i),
          :label => data['token'],
          :description => data['note'],
          :usage_limit => usage_limit
        }
      end

      def associate_host_collections(ak_id, server_group_ids)
        translated_ids = server_group_ids.collect { |sg_id| get_translated_id(:host_collections, sg_id) }
        puts "  Associating activation key [#{ak_id}] with host collections [#{translated_ids.join(', ')}]"
        @api.resource(:activation_keys).call(
          :add_host_collections,
          {
            :id => ak_id,
            :host_collection_ids => translated_ids
          })
      end

      def import_single_row(data)
        ak_hash = mk_ak_hash data
        ak = create_entity(:activation_keys, ak_hash, data['token'])
        if (data['server_group_id'])
          associate_host_collections(ak['id'], split_multival(data['server_group_id']))
        end
        @ak_content_views ||= {}
        @ak_content_views[ak['id'].to_i] ||= Set.new
        if data['base_channel_id']
          split_multival(data['base_channel_id']).each do |base_channel_id|
            @ak_content_views[ak['id'].to_i] <<
            get_translated_id(:content_views, base_channel_id)
          end
        else
          # if base channel id is empty,
          # 'Spacewalk Default' was used on Sat5
        end
        split_multival(data['child_channel_id']).each do |child_ch|
          @ak_content_views[ak['id'].to_i] << get_translated_id(:content_views, child_ch)
        end
      end

      def post_import(_data)
        @ak_content_views.each do |ak_id, cvs|
          ak = lookup_entity(:activation_keys, ak_id)
          ak_cv_hash = {}
          if cvs.size == 1
            ak_cv_hash[:content_view_id] = cvs.to_a[0]
          else
            # create composite content view
            cv_label = "ak_#{ak_id}"
            cv_versions = []
            cvs.each do |cv_id|
              cvvs = list_server_entities(:content_view_versions, {:content_view_id => cv_id})
              cvvs.each do |c|
                cv_versions << c['id']
              end
            end
            cv = lookup_entity_in_cache(:ak_content_views, 'label' => cv_label)
            if cv
              puts "  Content view #{cv_label} already created, reusing."
            else
              # create composite content view
              # for activation key purposes
              cv = create_entity(
                :ak_content_views,
                {
                  :organization_id => lookup_entity_in_cache(:organizations, {'label' => ak['organization']['label']})['id'],
                  :name => cv_label,
                  :label => cv_label,
                  :composite => true,
                  :descrption => "Composite content view for activation key #{ak['name']}",
                  :component_ids => cv_versions
                },
                cv_label)
              # publish the content view
              puts "  Publishing content view: #{cv['id']}"
              api_mapped_resource(:ak_content_views).call(:publish, { :id => cv['id'] })
            end
            ak_cv_hash[:content_view_id] = cv['id']
          end
          puts "  Associating activation key [#{ak_id}] with content view [#{ak_cv_hash[:content_view_id]}]"
          # associate the content view with the activation key
          update_entity(:activation_keys, ak_id, ak_cv_hash)
        end
      end

      def delete_single_row(data)
        unless @pm[:activation_keys][data['token']]
          puts to_singular(:activation_keys).capitalize + ' with id ' + data['token'] +
            " wasn't imported. Skipping deletion."
          return
        end
        ak = @cache[:activation_keys][get_translated_id(:activation_keys, data['token'])]
        delete_entity(:activation_keys, data['token'])
        delete_ak_content_view(ak['content_view']) if
          ak['content_view'] && was_translated(:ak_content_views, ak['content_view']['id'])
      end

      def delete_ak_content_view(cv)
        content_view = get_cache(:ak_content_views)[cv['id'].to_i]

        cv_versions = content_view['versions'].collect { |v| v['id'] }

        task = api_mapped_resource(:ak_content_views).call(
            :remove,
            {
              :id => content_view['id'],
              :content_view_version_ids => cv_versions
            })

        wait_for_task(task['id'], 1, 0)

        delete_entity_by_import_id(:ak_content_views, content_view['id'])
      end
    end
  end
end
