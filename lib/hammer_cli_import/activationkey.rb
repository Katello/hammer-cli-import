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
    class ActivationKeyImportCommand < BaseCommand
      include ImportTools::ContentView::Include
      include ImportTools::LifecycleEnvironment::Include

      command_name 'activation-key'
      reportname = 'activation-keys'
      desc _("Import Activation Keys (from spacewalk-report %s).") % (reportname)

      csv_columns 'token', 'org_id', 'note', 'usage_limit', 'base_channel_id', 'child_channel_id', 'server_group_id'

      persistent_maps :organizations, :host_collections, :content_views, :redhat_content_views,
                      :ak_content_views, :activation_keys

      def mk_ak_hash(data)
        usage_limit = 'unlimited'
        usage_limit = data['usage_limit'].to_i if data['usage_limit']
        debug "  Activation key usage_limit: #{usage_limit}"
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
        info "  Associating activation key [#{ak_id}] with host collections [#{translated_ids.join(', ')}]"
        api_call(
          :activation_keys,
          :add_host_collections,
          {
            :id => ak_id,
            :host_collection_ids => translated_ids
          })
      end

      def import_single_row(data)
        if data['base_channel_id'].nil?
          # if base channel id is empty,
          # 'Spacewalk Default' was used on Sat5
          info "Skipping activation-key #{data['token']}: Migrating activation-keys with " \
            "'Red Hat Satellite Default' as base channel is not supported."
          report_summary :skipped, :activation_keys
          return
        end
        ak_hash = mk_ak_hash data
        ak = create_entity(:activation_keys, ak_hash, data['token'])
        if (data['server_group_id'])
          associate_host_collections(ak['id'], split_multival(data['server_group_id']))
        end
        @ak_content_views ||= {}
        @ak_content_views[ak['id'].to_i] ||= Set.new
        if data['base_channel_id']
          split_multival(data['base_channel_id']).each do |base_channel_id|
            @ak_content_views[ak['id'].to_i] << begin
              get_translated_id(:redhat_content_views, [data['org_id'].to_i, base_channel_id])
            rescue HammerCLIImport::MissingObjectError
              begin
                get_translated_id(:content_views, base_channel_id)
              rescue HammerCLIImport::MissingObjectError
                error "Can't find content view for channel ID [#{base_channel_id}] for key [#{data['token']}]"
              end
            end
          end
        else
          # if base channel id is empty,
          # 'Spacewalk Default' was used on Sat5
          # Since we can not migrate them due to
          # bug 1126924, we skip it right at the beggining
          # of this function.
          debug ' Red Hat Satellite Default activation keys are not supported.'
        end
        split_multival(data['child_channel_id']).each do |child_ch|
          @ak_content_views[ak['id'].to_i] << begin
            get_translated_id(:redhat_content_views, [data['org_id'].to_i, child_ch])
          rescue HammerCLIImport::MissingObjectError
            begin
              get_translated_id(:content_views, child_ch)
            rescue HammerCLIImport::MissingObjectError
              error "Can't find content view for channel ID [#{child_ch}] for key [#{data['token']}]"
            end
          end
        end
      end

      def post_import(_csv_file)
        return unless @ak_content_views
        @ak_content_views.each do |ak_id, cvs|
          if cvs.include? nil
            warn "Skipping content view association for activation key [#{ak_id}]. Dependent content views not ready."
            next
          end
          handle_missing_and_supress "processing activation key #{ak_id}" do
            ak = lookup_entity(:activation_keys, ak_id)
            ak_cv_hash = {}
            org_id = lookup_entity_in_cache(:organizations, {'label' => ak['organization']['label']})['id']
            ak_cv_hash[:content_view_id] = create_composite_content_view(
              :ak_content_views,
              org_id,
              "ak_#{ak_id}",
              "Composite content view for activation key #{ak['name']}",
              cvs)
            ak_cv_hash[:environment_id] = get_env(org_id, 'Library')['id']
            ak_cv_hash[:organization_id] = org_id
            if ak_cv_hash[:content_view_id]
              info "  Associating activation key [#{ak_id}] with content view [#{ak_cv_hash[:content_view_id]}]"
              # associate the content view with the activation key
              update_entity(:activation_keys, ak_id, ak_cv_hash)
            else
              info '  Skipping content-view associations.'
            end
          end
        end
      end

      def delete_single_row(data)
        unless @pm[:activation_keys][data['token']]
          info to_singular(:activation_keys).capitalize + ' with id ' + data['token'] +
            " wasn't imported. Skipping deletion."
          return
        end
        ak = @cache[:activation_keys][get_translated_id(:activation_keys, data['token'])]
        delete_entity(:activation_keys, data['token'])
        delete_content_view(ak['content_view']['id'].to_i, :ak_content_views) if
          ak['content_view'] && was_translated(:ak_content_views, ak['content_view']['id'])
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
