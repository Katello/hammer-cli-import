# If in need of trying things, copy asyncreactor to current directorry

require './asynctasksreactor'

class Experiment
  include HammerCLIImport::AsyncTasksReactor::Include

  def initialize
    atr_init
    @start_time = Time.now
  end

  def finished_task(n)
    Time.now - @start_time > n
  end

  def get_statuses(ns)
    puts "Getting statuses at about #{Time.now - @start_time}"
    res = {}
    ns.each do |n|
      res[n] = { :id => n, :finished => (finished_task n) }
    end
    res
  end

  def get_finished(ns)
    ret = []
    get_statuses(ns).each { |key, val| ret << key if val[:finished] }
    ret
  end
end

class SubExperiment < Experiment
  def some_call(*list)
    p list
  end

  def run
    postpone_till [1, 2, 3] do
      some_call 1
    end

    postpone_till [1, 2, 3] do
      some_call 4
    end

    postpone_till [2, 4] do
      some_call 2
      postpone_till [7] do
        p 42
      end
    end

    sleep 10

    postpone_till [2] do
      some_call 3
    end

    sleep 10

    atr_exit
  end
end

SubExperiment.new.run

# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
