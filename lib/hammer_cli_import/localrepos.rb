# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'
require 'uri'

module HammerCLIImport
  class ImportCommand
    class LocalRepositoryImportCommand < BaseCommand
      command_name 'local-repo'
      desc 'Import local repositories.'

      csv_columns 'org_id', 'channel_id', 'channel_label'

      persistent_maps :organizations, :repositories
      persistent_map :products, [{'org_id' => Fixnum}, {'label' => String}], ['sat6' => Fixnum]


      option ['--sync'], :flag, 'Synchronize local repositories', :default => false
      option ['--dir'], 'DIR', 'Export directory'

      def directory
        option_dir || File.dirname(option_csv_file)
      end

      #######
      # -> DUPE
      def mk_product_hash(data, product_name)
        {
          :name => product_name,
          :organization_id => lookup_entity(:organizations, get_translated_id(:organizations, data['org_id'].to_i))['label']
        }
      end

      def mk_repo_hash(data, product_id)
        {
          :name => "Local-repository-for-#{data['channel_label']}",
          :product_id => product_id,
          :url => 'file://' + File.join(directory, data['org_id'], data['channel_id']),
          :content_type => 'yum'
        }
      end

      def sync_repo(repo)
        @api.resource(:repositories).call(:sync, {:id => repo['id']})
      end
      # <-
      #######


      # Couple of possible encodings.... (+ matching decodings) (Haskell-ish syntax)
      #
      # > sqrtBig n = head . dropWhile ((n<).(^2)) $ iterate f n where
      # >     f x = (x + n `div` x) `div` 2
      #
      # > enc1 x y = (x + y)*(x + y + 1) `div` 2 + x 
      #
      # > dec1 0 = (0,0)
      # > dec1 n = (c, a+d-c) where
      # >     a = sqrtBig (n*2)
      # >     b = n - enc1 0 (a) 
      # >     c = (a + b) `mod` a
      # >     d = b `div` a
      #
      # > enc2 x y = 2^x * (y*2+1)
      #
      # > dec2 n = (x,y) where
      # >     (x, y') = f 0 n where
      # >         f a b = if m == 0 then f (a+1) d else (a,b) where (d, m) = b `divMod` 2
      # >     y = (y' - 1) `div` 2
      #
      # Choose wisely ;-)
      def encode(a, b)
        - (2 ** a) * (2*b + 1)
      end

      def import_single_row(data)
        product_name = 'Local-repositories'
        composite_id = [data['org_id'].to_i, product_name]
        product_hash = mk_product_hash data, product_name
        product_id = create_entity(:products, product_hash, composite_id)['id'].to_i

        repo_hash = mk_repo_hash(data, product_id)
        repo = create_entity(:repositories, repo_hash, encode(data['org_id'].to_i, data['channel_id'].to_i))

        sync_repo repo if option_sync?
      end
    end
  end
end
