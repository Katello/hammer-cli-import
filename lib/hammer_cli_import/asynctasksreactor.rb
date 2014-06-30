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

# Note to future self (and possibly others): unless there is a
# (serious) bug here, you probably do not want to modify this code.
require 'thread'

module HammerCLIImport
  # Reactor for async tasks
  # Include submodule should be included in class that
  # implements @get_finished@ that takes list of UUIDS
  # and returns list of finished UUIDS.
  module AsyncTasksReactor
    module Include
      # Call from init
      def atr_init
        # Will create thread on demand
        @thread = nil

        @mutex = Mutex.new
        @task_map = {}
        @thread_finish = false
      end

      # Call to pospone execution of @block@ till all tasks are finished
      def postpone_till(uuids, &block)
        puts "Registering tasks for uuids: #{uuids.inspect}."
        p = Proc.new(&block)
        uuids.sort!
        if @mutex.owned?
          add_task uuids, p
        else
          @mutex.synchronize { add_task uuids, p }
        end
        start_async_task_thread
      end

      # Has to be called before main thread ends.
      def atr_exit
        puts 'Waiting for async tasks to finish' unless @task_map.empty?
        @mutex.synchronize do
          @thread_finish = true
          @thread.wakeup
        end
        @thread.join
      rescue NoMethodError
        nil
      end

      private

      def add_task(uuids, p)
        fail ThreadError, 'need to own mutex' unless @mutex.owned?
        @task_map[uuids] ||= []
        @task_map[uuids] << p
        @thread.wakeup if @thread && @thread.status == 'sleep'
      end

      def start_async_task_thread
        puts 'Starting thread for async tasks' unless @thread
        @thread ||= Thread.new do
          loop do
            all_uuids = @mutex.synchronize do
              @task_map.keys.flatten.uniq
            end
            finished = get_finished all_uuids

            @mutex.synchronize do

              @task_map.keys.each do |uuids|
                next unless (uuids - finished).empty?
                puts "Condition #{uuids} met"
                @task_map[uuids].each do |task|
                  task.call
                end
                @task_map.delete uuids
              end

              puts "Waiting tasks: #{@task_map.values.reduce(0) { |a, e| a + e.size }}"
              if @task_map.empty?
                # This can not be removed in favour of later one, as
                # deadlock may occur.
                Thread.current.exit if @thread_finish
                @mutex.sleep
              else
                @mutex.sleep 1
              end

              # Avoid one more loop if we know we are going to finish anyway...
              # We have to re-check emptyness, as we were in sleep and anything
              # could have happened
              Thread.current.exit if @thread_finish && @task_map.empty?
            end
          end
        end
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
