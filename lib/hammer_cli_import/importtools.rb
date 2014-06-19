# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby

# Modules to help with imports. To be used as Extend/Import on classes that inherit
# from module HammerCLIImport::BaseCommand.
module ImportTools
  module Repository
    module Extend
      def add_repo_options
        option ['--sync'], :flag, 'Synchronize imported repositories', :default => false
        option ['--synchronous'], :flag, 'Wait for repository synchronization to finish', :default => false

        validate_options do
          option(:option_sync).required if option(:option_synchronous).exist?
        end
      end
    end

    module Include
      def repo_synced?(repo)
        raise ArgumentError, 'nil is not a valid repository' if repo.nil?

        info = lookup_entity(:repositories, repo['id'], true)
        return false unless info['sync_state'] == 'finished'
        Time.parse(info['last_sync']) > Time.parse(info['updated_at'])
      end

      def sync_repo(repo)
        return unless option_sync?
        task = api_call(:repositories, :sync, {:id => repo['id']})
        puts 'Sync started!'
        return unless option_synchronous?
        wait_for_task task['id']
      end
    end
  end
end
