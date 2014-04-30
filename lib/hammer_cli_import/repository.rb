# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'
require 'uri'

module HammerCLIImport
  class ImportCommand
    class RepositoryImportCommand < BaseCommand
      command_name 'repository'
      desc 'Import repositories.'

      csv_columns 'id', 'org_id', 'repo_label', 'source_url', 'repo_type'

      persistent_maps :organizations, :repositories
      persistent_map :products, [{'org_id' => Fixnum}, {'label' => String}], ['sat6' => Fixnum]

      option ['--sync'], :flag, 'Synchronize imported repositories', :default => false

      def mk_product_hash(data, product_name)
        {
          :name => product_name,
          :organization_id => lookup_entity(:organizations, get_translated_id(:organizations, data['org_id'].to_i))['label']
        }
      end

      def mk_repo_hash(data, product_id)
        {
          :name => data['repo_label'],
          :product_id => product_id,
          :url => data['source_url'],
          :content_type => data['repo_type']
        }
      end

      def sync_repo(repo)
        @api.resource(:repositories).call(:sync, {:id => repo['id']})
      end

      def import_single_row(data)
        begin
          product_name = URI.parse(data['source_url']).host.split('.')[-2, 2].join('.').upcase
        rescue
          puts 'Skipping ' + data['repo_label'] + ' ' + to_singular(:repositories) + ' import, invalid source_url.'
          return
        end
        product_hash = mk_product_hash(data, product_name)
        composite_id = [data['org_id'].to_i, product_name]
        product_id = create_entity(:products, product_hash, composite_id)['id']
        repo_hash = mk_repo_hash data, product_id
        repo = create_entity(:repositories, repo_hash, data['id'].to_i)
        if option_sync?
          sync_repo repo
        end
      end

      def delete_single_row(data)
        # check just becasue we're calling get_translated_id
        unless @pm[:repositories][data['id'].to_i]
          puts to_singular(:repositories).capitalize + ' with id ' + data['id'] + " wasn't imported. Skipping."
          return
        end
        # find out product id
        repo_id = get_translated_id(:repositories, data['id'].to_i)
        product_id = @cache[:repositories][repo_id]['product']['id']
        # delete repo
        delete_entity(:repositories, data['id'].to_i)
        # delete its product, if it's not associated with any other repositories
        product = lookup_entity(:products, product_id, true)
        if product['repository_count'] == 0
          delete_entity_by_import_id(:products, product_id)
        end
      end
    end
  end
end
