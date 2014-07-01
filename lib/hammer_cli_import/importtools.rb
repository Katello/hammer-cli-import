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

# Modules to help with imports. To be used as Extend/Import on classes that inherit
# from module HammerCLIImport::BaseCommand.
module ImportTools
  module Repository
    module Extend
      def add_repo_options
        option ['--synchronize'], :flag, 'Synchronize imported repositories', :default => false
        option ['--wait'], :flag, 'Wait for repository synchronization to finish', :default => false

        validate_options do
          option(:option_synchronize).required if option(:option_wait).exist?
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
        return unless option_synchronize?
        task = api_call(:repositories, :sync, {:id => repo['id']})
        puts 'Sync started!'
        return unless option_wait?
        wait_for_task task['id']
      end
    end
  end

  module Task
    module Include
      # [uuid] -> [uuid]
      def filter_finished_tasks(uuids)
        ret = []
        get_tasks_statuses(uuids).each do |uuid, stat|
          ret << uuid if stat['state'] == 'stopped'
        end
        ret
      end

      private

      # [uuid] -> {uuid: task_status}
      def get_tasks_statuses(uuids)
        searches = uuids.collect { |uuid| {:type => :task, :task_id => uuid} }
        ret = api_call :foreman_tasks, :bulk_search, {:searches => searches}
        statuses = {}
        ret.each do |status_result|
          status_result['results'].each do |task_info|
            statuses[task_info['id']] = task_info
          end
        end
        statuses
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
