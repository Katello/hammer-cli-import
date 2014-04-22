# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'
require 'csv'
require 'uri'

module HammerCLIImport
  class ImportCommand
    class RepositoryImportCommand < BaseCommand

      command_name "repository"
      desc "Import repositories."

      csv_columns 'id', 'org_id', 'repo_label', 'source_url', 'repo_type'

      persistent_maps :organizations, :products, :repositories

      def mk_product_hash(data, product_name)
        {
          :name => product_name,
          :organization_id => lookup_entity(:organizations, get_translated_id(:organizations, data["org_id"].to_i))["label"]
        }
      end

      def mk_repo_hash(data, product_id)
        {
          :name => data['repo_label'],
          :product_id => product_id,
          :url => data["source_url"],
          :content_type => data["repo_type"]
        }
      end

      def import_single_row(data)
        begin
          product_name = URI.parse(data["source_url"]).host.split(".")[-2,2].join(".").upcase
        rescue
          puts "Skipping " + data["repo_label"] + " " + to_singular(:repositories) + " import, invalid source_url."
          return
        end
        p product_name
        product_hash = mk_product_hash(data, product_name)
        p product_hash
        composite_id = [data["org_id"].to_i, product_name]
        product_id = create_entity(:products, product_hash, composite_id)["id"]
        repo_hash = mk_repo_hash data, product_id
        p data
        create_entity(:repositories, repo_hash, data["id"].to_i)
      end
    end
  end
end
