require 'hammer_cli'
require 'hammer_cli_import'
require 'json'
require 'csv'

module HammerCLIImport
  class ImportCommand
    class ChannelDiscoveryCommand < HammerCLI::Apipie::Command
      command_name 'repository-discovery'
      desc 'Discover all Repositories accessible to any Organization'

      option ['--csv-channels'],
             'FILE_NAME',
             'CSV of channels synchronized to source Satellite instance' do |filename|
        raise ArgumentError, "File #{filename} not found!" unless File.exist? filename
        filename
      end

      option ['--repository-map'],
             'FILE_NAME',
             'JSON file mapping channel-labels to repository information',
             :default => '/etc/hammer/cli.modules.d/channel_data.json'

      option ['--dry-run'], :flag, 'Only show the repositories that would be enabled', :default => false

      # We provide the output of this process in the distribution of the tool - this code exists
      # only if someone wants to do their own mapping (?!?)
      #
      # Fun heuristics below
      #
      # cdn-map file is JSON, [{'channel'=>c, 'path'=>p},...]
      # In 'path', if we can find the 'basearch', we can (usually) derive the
      # right 'releasever' - path-fmt is .../$releasever/$basearch...'
      # solaris breaks things - skip it
      # fasttrack has no $releasever
      # repo-set-urls don't end in /Package
      #
      # Return a map keyed by channel-label, returns map of
      #   {url, version, arch, set-url}
      # We should be able to match set-url to repo-set['url']
      # Fun!
      def read_channel_map(filename)
        rc = Hash.new
        parsed = ''
        File.open(filename, 'r') do |f|
          json = f.read()
          # [ {'channel', 'path'}...]
          parsed = JSON.parse(json)
        end

        archs = %w(i386 x86_64 s390x s390 ppc64 ppc ia64)
        parsed.each do |c|
          path_lst = c['path'].split('/')
          arch_ndx = path_lst.index{|a| archs.include?(a)}
          if arch_ndx.nil?
            puts 'Arch not found: [' + c['path'] + '], skipping...'
            next
          end
          vers_ndx = arch_ndx - 1
          channel_data = {
            'url' => c['path'],
            'version' => path_lst[vers_ndx],
            'arch' => path_lst[arch_ndx]
          }
          path_lst[arch_ndx] = '$basearch'
          path_lst[vers_ndx] = '$releasever' unless path_lst[1] == 'fastrack'
          repo_set_url = path_lst[0..-2].join('/')
          channel_data['set-url'] = repo_set_url
          rc[c['channel']] = channel_data
        end

        return rc
      end

      def get_orgs
        orgs = @api.resource(:organizations).call(:index, 'per_page' => 999999)
        return orgs['results']
      end

      def get_products(org)
        prods = @api.resource(:products).call(:index, 'organization_id' => org['id'], 'per_page' => 999999)
        return prods['results']
      end

      def get_repository_sets(org, prod)
        repo_sets = @api.resource(:repository_sets).call(:index, 'organization_id' => org['id'], 'product_id' => prod['id'], 'per_page' => 999999)
        return repo_sets['results']
      end

      # Find channel-labels for RH channels (org_id = nil)
      def read_exported_channels(filename)
        channels = []
        return channels unless File.exist? filename

        # channel_label,channel_name,number_of_packages,org_id
        CSV.foreach(filename) do |col|
          channels << col[0] if col[3].nil?
        end
        return channels
      end

      # Hydrate the channel-to-repository-data mapping struct
      def read_channel_mapping_data(filename)
        channel_map = {}
        return channel_map unless File.exist? filename

        File.open(filename, 'r') do |f|
          json = f.read()
          channel_map = JSON.parse(json)
        end
        return channel_map
      end

      # Construct reverse-map {set-url {channel-label}, ...}
      def construct_repo_map(channel_map, channels)
        repo_map = {}
        channels.each do |c|
          repo = channel_map[c]
          next if repo.nil?

          repo_map[repo['set-url']] = c
        end
        return repo_map
      end

      # Given a repository-set and a channel-to-repo info for that channel,
      # enable the correct repository
      def enable_repos(org, prod, repo_set, info)
        puts "Enabling #{info['url']}"

        begin
          @api.resource(:repository_sets).call(:enable,
                                               'organization_id' => org['id'],
                                               'product_id' => prod['id'],
                                               'id' => repo_set['id'],
                                               'basearch' => info['arch'],
                                               'releasever' => info['version']) unless option_dry_run?
        rescue RestClient::Exception  => e
          throw e unless e.http_code == 409
          puts "...already enabled."
        end
      end

      def execute
        # Set up/hydrate our data structures
        rh_channels = read_exported_channels(option_csv_channels)
        channel_to_repo = read_channel_mapping_data(option_repository_map)
        repo_to_channel = construct_repo_map(channel_to_repo, rh_channels)

        # initialize apipie binding
        @api = ApipieBindings::API.new(
        {
          :uri => HammerCLI::Settings.get(:foreman, :host),
          :username => HammerCLI::Settings.get(:foreman, :username),
          :password => HammerCLI::Settings.get(:foreman, :password),
          :api_version => 2
        })

        # Go find all our repository-sets
        get_orgs.each do |o|
          get_products(o).each do |p|
            get_repository_sets(o, p).each do |rs|
              # Do we care about a channel that matches this repo-set?
              matching_channel = repo_to_channel[rs['contentUrl']]
              next if matching_channel.nil?

              # Get the repo-set-info that applies to that channel
              repo_set_info = channel_to_repo[matching_channel]
              next if repo_set_info.nil?

              # Turn on the specific repository
              enable_repos(o, p, rs, repo_set_info)
            end
          end
        end
        HammerCLI::EX_OK
      end
    end
  end
end

