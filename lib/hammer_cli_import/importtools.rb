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

require 'logger'

module ImportTools
  module Repository
    module Extend
      def add_repo_options
        option ['--synchronize'], :flag, 'Synchronize imported repositories', :default => false
        option ['--wait'], :flag, 'Wait for repository synchronization to finish', :default => false

        add_async_tasks_reactor_options

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

        ## (Temporary) workaround for 1131954
        ## updated_at is updated after sync for some reason...
        # begin
        #   Time.parse(info['last_sync']) > Time.parse(info['updated_at'])
        # rescue
        #   false
        # end
        true
      end

      def sync_repo(repo)
        return unless option_synchronize?
        task = api_call(:repositories, :sync, {:id => repo['id']})
        debug "Sync of repo #{repo['id']} started!"
        return unless option_wait?
        wait_for_task task['id']
      end

      def sync_repo2(repo)
        task = api_call(:repositories, :sync, {:id => repo['id']})
        debug "Sync of repo #{repo['id']} started!"
        task['id']
      rescue
        uuid = workaround_1116063 repo['id']
        info 'Sync already running!'
        uuid
      end

      def with_synced_repo(repo, &block)
        # So we can not give empty block
        if block_given?
          action = block
        else
          action = proc {}
        end

        if repo_synced?(repo)
          action.call
        else
          uuid = sync_repo2 repo
          postpone_till([uuid], &action) if option_wait?
        end
      end

      private

      # When BZ 1116063 get fixed, this might
      # be simplified using either
      # > api_call(:repositories, :show, {'id' => 1})
      # or maybe with
      # > api_call(:sync, :index, {:repository_id => 1})
      def workaround_1116063(repo_id)
        res = api_call :foreman_tasks, :bulk_search, \
                       :searches => [{:type => :resource, :resource_type => 'Katello::Repository', :resource_id => repo_id}]

        res.first['results'] \
          .select { |x| x['result'] != 'error' } \
          .max_by { |x| Time.parse(x['started_at']) }['id']
      end
    end
  end

  module LifecycleEnvironment
    module Include
      def get_env(org_id, name = 'Library')
        @lc_environments ||= {}
        @lc_environments[org_id] ||= {}
        unless @lc_environments[org_id][name]
          res = api_call :lifecycle_environments, :index, {:organization_id => org_id, :name => name}
          @lc_environments[org_id][name] = res['results'].find { |x| x['name'] == name }
        end
        @lc_environments[org_id][name]
      end
    end
  end

  module Task
    module Include
      # [uuid] -> {uuid => {:finished => bool, :progress => Float}}
      def annotate_tasks(uuids)
        ret = {}
        get_tasks_statuses(uuids).each do |uuid, stat|
          ret[uuid] = { :finished => stat['state'] == 'stopped',
                        :progress => stat['progress']}
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

  module ContentView
    module Include
      def publish_content_view(id, entity_type = :content_views)
        mapped_api_call entity_type, :publish, {:id => id}
        rescue => e
          warn "Publishing of #{to_singular(entity_type)} [#{id}] failed with #{e.class}: #{e.message}"
      end

      def create_composite_content_view(entity_type, org_id, cv_label, cv_description, cvs)
        return nil if cvs.empty?
        if cvs.size == 1
          return cvs.to_a[0]
        else
          # create composite content view
          cv_versions = []
          cvs.each do |cv_id|
            cvvs = list_server_entities(:content_view_versions, {:content_view_id => cv_id})
            cvvs.each do |c|
              cv_versions << c['id']
            end
          end
          cv = lookup_entity_in_cache(entity_type, 'label' => cv_label)
          if cv
            info "  Content view #{cv_label} already created, reusing."
          else
            # create composite content view
            # for activation key purposes
            cv = create_entity(
              entity_type,
              {
                :organization_id => org_id,
                :name => cv_label,
                :label => cv_label,
                :composite => true,
                :description => cv_description,
                :component_ids => cv_versions
              },
              cv_label)
            # publish the content view
            info "  Publishing content view: #{cv['id']}"
            publish_content_view(cv['id'], entity_type)
          end
          return cv['id']
        end
      end

      # use entity_type as parameter to be able to re-use the method for
      # :content_views, :ak_content_views, :redhat_content_views, ...
      def delete_content_view(cv_id, entity_type = :content_views)
        raise "delete_content_view with #{entity_type}" unless map_target_entity[entity_type] == :content_views

        content_view = get_cache(entity_type)[cv_id]

        if content_view['versions'] && !content_view['versions'].empty?
          cv_version_ids = content_view['versions'].collect { |v| v['id'] }

          begin
            task = mapped_api_call(
              entity_type,
              :remove,
              {
                :id => content_view['id'],
                :content_view_version_ids => cv_version_ids
              })

            wait_for_task(task['id'], 1, 0)
          rescue => e
            warn "Failed to remove versions of content view [#{cv_id}] with #{e.class}: #{e.message}"
          end
        else
          debug "No versions found for #{to_singular(entity_type)} #{cv_id}"
        end

        delete_entity_by_import_id(entity_type, content_view['id'])
      end
    end
  end

  module ImportLogging
    module Extend
      def add_logging_options
        # Logging options
        # quiet = go to logfile only
        # verbose = all output goes to STDOUT as well as log
        # debug = enable debug-output
        # default = no debug, only PROGRESS-and-above to STDOUT
        option ['--quiet'], :flag, 'Be silent - no output to STDOUT', :default => false
        option ['--debug'], :flag, 'Turn on debugging-information', :default => false
        option ['--verbose'],
               :flag,
               'Be noisy - everything goes to STDOUT and to a logfile',
               :default => false
        option ['--logfile'],
               'LOGFILE',
               'Where output is logged to',
               :default => File.expand_path('~/import.log')
      end
    end

    module Include
      def setup_logging
        @curr_lvl = Logger::INFO
        @curr_lvl = Logger::DEBUG if option_debug?

        @logger = Logger.new(File.new(option_logfile, 'a'))
        @logger.level = @curr_lvl
      end

      def debug(s)
        log(Logger::DEBUG, s)
      end

      def info(s)
        log(Logger::INFO, s)
      end

      def progress(s)
        log(Logger::INFO, s, true)
      end

      def warn(s)
        log(Logger::WARN, s)
      end

      def error(s)
        log(Logger::ERROR, s)
      end

      def fatal(s)
        log(Logger::FATAL, s)
      end

      def logtrace(e)
        @logger.log(Logger::ERROR, (e.backtrace.join "\n"))
      end

      def log(lvl, s, always = false)
        @logger.log(lvl, s)
        return if option_quiet?

        if always
          puts s
        elsif option_verbose?
          puts s if lvl >= @curr_lvl
        else
          puts s if lvl > @curr_lvl
        end
      end
    end
  end

  module Exceptional
    module Include
      def handle_missing_and_supress(what, &block)
        block.call
      rescue HammerCLIImport::MissingObjectError => moe
        error moe.message
      rescue => e
        error "Caught #{e.class}:#{e.message} while #{what}"
        logtrace e
      end

      # this method catches everything sent to stdout and stderr
      # and disallows any summary changes
      #
      # this is a bad hack, but we need it, as sat6 cannot tell,
      # whether there're still content hosts associated with a content view
      # so we try to delete system content views silently
      def silently(&block)
        summary_backup = @summary.clone
        $stdout, $stderr = StringIO.new, StringIO.new
        block.call
        ensure
          $stdout, $stderr = STDOUT, STDERR
          @summary = summary_backup
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
