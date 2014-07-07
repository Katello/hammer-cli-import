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

#  Main thread                     Thread for async tasks
#     |                                 |
#     |  enq task          deq task     |<---.
#     |'----------> Queue ----------->  |     |
#     |                                 |'---'
#     |                                 |
#     V                                 V
require 'thread'

module HammerCLIImport
  # Reactor for async tasks
  # Include submodule should be included in class that
  # implements @filter_finished_tasks@ that takes list
  # of UUIDS and returns list of finished UUIDS.
  module AsyncTasksReactor
    module Include
      # Call from init
      def atr_init
        # Will create thread on demand
        @thread = nil

        @mutex = Mutex.new
        @queue = Queue.new
        @task_map = {}
        @thread_finish = false
        @async_tasks_todo = 0
        @async_tasks_done = 0
      end

      # Call to pospone execution of @block@ till all tasks are finished
      # Never ever use @return@ inside provided do block.
      def postpone_till(uuids, &block)
        if uuids.empty?
          puts 'Nothing to wait for, running in main thread.'
          block.call
          return
        end
        puts "Registering tasks for uuids: #{uuids.inspect}."
        uuids.sort!
        @queue.enq([uuids, block])
        start_async_task_thread
        nil
      end

      # Has to be called before main thread ends.
      def atr_exit
        puts 'Waiting for async tasks to finish' unless @task_map.empty?
        @mutex.synchronize do
          @thread_finish = true
          @thread.run
        end
        @thread.join
      rescue NoMethodError
        nil
      end

      private

      def add_task(uuids, p)
        @async_tasks_todo += 1
        @task_map[uuids] ||= []
        @task_map[uuids] << p
      end

      def pick_up_tasks_from_the_queue
        Thread.stop if @mutex.synchronize do
          if @task_map.empty? && @queue.empty?
            if @thread_finish
              puts 'Exiting thread (exit requested, all tasks done).'
              Thread.exit
            else
              true
            end
          else
            false
          end
        end

        # Do at most what we have at some point
        @queue.size.times do
          begin
            uuids, p = @queue.deq true
            add_task uuids, p
          rescue ThreadError
            break
          end
        end
      end

      def start_async_task_thread
        puts 'Starting thread for async tasks' unless @thread
        @thread ||= Thread.new do
          loop do
            some_tasks_done = false
            pick_up_tasks_from_the_queue

            next if @task_map.empty?

            all_uuids = @task_map.keys.flatten.uniq
            finished = filter_finished_tasks all_uuids

            @task_map.keys.each do |uuids|
              next unless (uuids - finished).empty?
              puts "Condition #{uuids.inspect} met"
              @task_map[uuids].each do |task|
                begin
                  task.call
                rescue => e
                  puts "Exception caught while executing post-#{uuids.inspect}:"
                  puts e.inspect
                end
                @async_tasks_done += 1
                some_tasks_done = true
              end
              @task_map.delete uuids
            end

            print = @mutex.synchronize do
              some_tasks_done || @thread_finish
            end
            puts "Asynchronous tasks: #{@async_tasks_done} of #{@async_tasks_todo + @queue.size} done." if print

            sleep 1 unless @task_map.empty?
          end
        end
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
