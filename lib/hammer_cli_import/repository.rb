# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
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
require 'hammer_cli'
require 'uri'

module HammerCLIImport
  class ImportCommand
    class RepositoryImportCommand < BaseCommand
      extend ImportTools::Repository::Extend
      include ImportTools::Repository::Include

      command_name 'repository'
      desc 'Import repositories.'

      csv_columns 'id', 'org_id', 'repo_label', 'source_url', 'repo_type'

      persistent_maps :organizations, :repositories, :products

      add_repo_options

      def mk_product_hash(data, product_name)
        {
          :name => product_name,
          :organization_id => get_translated_id(:organizations, data['org_id'].to_i)
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

        sync_repo repo unless repo_synced? repo
      end

      def delete_single_row(data)
        # check just becasue we're calling get_translated_id
        unless @pm[:repositories][data['id'].to_i]
          puts to_singular(:repositories).capitalize + ' with id ' + data['id'] + " wasn't imported. Skipping deletion."
          return
        end
        # find out product id
        repo_id = get_translated_id(:repositories, data['id'].to_i)
        product_id = lookup_entity(:repositories, repo_id)['product']['id']
        # delete repo
        delete_entity(:repositories, data['id'].to_i)
        # delete its product, if it's not associated with any other repositories
        product = lookup_entity(:products, product_id, true)

        delete_entity_by_import_id(:products, product_id) if product['repository_count'] == 0
      end
    end
  end
end
