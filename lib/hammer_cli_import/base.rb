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

require 'csv'
require 'json'
require 'set'

require 'apipie-bindings'
require 'hammer_cli'

module HammerCLIImport
  class MissingObjectError < RuntimeError
  end

  class ImportRecoveryError < RuntimeError
  end

  class BaseCommand < HammerCLI::Apipie::Command
    extend PersistentMap::Extend
    extend ImportTools::ImportLogging::Extend
    extend AsyncTasksReactor::Extend

    include PersistentMap::Include
    include ImportTools::ImportLogging::Include
    include ImportTools::Task::Include
    include ImportTools::Exceptional::Include
    include AsyncTasksReactor::Include

    def initialize(*list)
      super(*list)

      # wrap API parameters into extra hash
      @wrap_out = {
        :users => :user,
        :template_snippets => :config_template
      }
      # APIs return objects encapsulated in extra hash
      #@wrap_in = {:organizations => 'organization'}
      @wrap_in = {}
      # entities that needs organization to be listed
      @prerequisite = {
        :activation_keys => :organizations,
        :content_views => :organizations,
        :content_view_versions => :organizations,
        :host_collections => :organizations,
        :products => :organizations,
        :repositories => :organizations,
        :repository_sets => :products,
        :hosts => :organizations
      }
      # cache imported objects (created/lookuped)
      @cache = {}
      class << @cache
        def []=(key, val)
          raise "@cache: #{val.inspect} is not a hash!" unless val.is_a? Hash
          super
        end
      end
      @summary = {}
      # Initialize AsyncTaskReactor
      atr_init

      server = (HammerCLI::Settings.settings[:_params] &&
                 HammerCLI::Settings.settings[:_params][:host]) ||
        HammerCLI::Settings.get(:foreman, :host)
      username = (HammerCLI::Settings.settings[:_params] &&
                   HammerCLI::Settings.settings[:_params][:username]) ||
        HammerCLI::Settings.get(:foreman, :username)
      password = (HammerCLI::Settings.settings[:_params] &&
                  HammerCLI::Settings.settings[:_params][:password]) ||
        HammerCLI::Settings.get(:foreman, :password)
      @api = ApipieBindings::API.new({
                                       :uri => server,
                                       :username => username,
                                       :password => password,
                                       :api_version => 2
                                     })
    end

    # What spacewalk-report do we expect to use for a given subcommand
    class << self; attr_accessor :reportname end

    option ['--csv-file'], 'FILE_NAME', 'CSV file with data to be imported', :required => true \
    do |filename|
      raise ArgumentError, "File #{filename} does not exist" unless File.exist? filename
      missing = CSVHelper.csv_missing_columns filename, self.class.csv_columns
      raise ArgumentError, "Bad CSV file #{filename}, missing columns: #{missing.inspect}" unless missing.empty?
      filename
    end

    option ['--delete'], :flag, 'Delete entities from CSV file', :default => false

    # TODO: Implement logic for verify
    # option ['--verify'], :flag, 'Verify entities from CSV file'

    option ['--recover'], 'RECOVER', 'Recover strategy, can be: rename (default), map, none', :default => :rename \
    do |strategy|
      raise ArgumentError, "Unknown '#{strategy}' strategy argument." \
        unless [:rename, :map, :none].include? strategy.to_sym
      strategy.to_sym
    end
    add_logging_options

    class << self
      # Which columns have to be be present in CSV.
      def csv_columns(*list)
        return @csv_columns if list.empty?
        raise 'set more than once' if @csv_columns
        @csv_columns = list
      end
    end

    class << self
      # Initialize API. Needed to be called before any +api_call+ calls.
      # If used in shell, it may be called multiple times
      def api_init
        @api = HammerCLIForeman.foreman_api_connection.api
        nil
      end

      # Call API. Ideally accessed via +api_call+ instance method.
      # This is supposed to be the only way to access @api.
      def api_call(resource, action, params = {}, headers = {}, dbg = false)
        if resource == :organizations && action == :create
          params[:organization] ||= {}
          params[:organization][:name] = params[:name]
        end
        @api.resource(resource).call(action, params, headers)
      rescue
        error("Error on api.resource(#{resource.inspect}).call(#{action.inspect}, #{params.inspect}):") if dbg
        raise
      end
    end

    # Call API. Convenience method for calling +api_call+ class method.
    def api_call(*list)
      self.class.api_call(*list)
    end

    # Call API on corresponding resource (defined by +map_target_entity+).
    def mapped_api_call(entity_type, *list)
      api_call(map_target_entity[entity_type], *list)
    end

    def data_dir
      File.join(File.expand_path('~'), '.transition_data')
    end

    # This method is called to process single CSV line when
    # importing.
    def import_single_row(_row)
      error 'Import not implemented.'
    end

    # This method is called to process single CSV line when
    # deleting
    def delete_single_row(_row)
      error 'Delete not implemented.'
    end

    def get_cache(entity_type)
      @cache[map_target_entity[entity_type]]
    end

    def load_cache
      maps.collect { |map_sym| map_target_entity[map_sym] } .uniq.each do |entity_type|
        list_server_entities entity_type
      end
    end

    def lookup_entity(entity_type, entity_id, online_lookup = false)
      if (!get_cache(entity_type)[entity_id] || online_lookup)
        get_cache(entity_type)[entity_id] = mapped_api_call(entity_type, :show, {'id' => entity_id})
      else
        debug "#{to_singular(entity_type).capitalize} #{entity_id} taken from cache."
      end
      return get_cache(entity_type)[entity_id]
    end

    def was_translated(entity_type, import_id)
      return @pm[entity_type].to_hash.value?(import_id)
    end

    def _compare_hash(entity_hash, search_hash)
      equal = nil
      search_hash.each do |key, value|
        if value.is_a? Hash
          equal = _compare_hash(entity_hash[key], search_hash[key])
        else
          equal = entity_hash[key] == value
        end
        return false unless equal
      end
      return true
    end

    def lookup_entity_in_cache(entity_type, search_hash)
      get_cache(entity_type).each do |_entity_id, entity_hash|
        return entity_hash if _compare_hash(entity_hash, search_hash)
      end
      return nil
    end

    def lookup_entity_in_array(array, search_hash)
      return nil if array.nil?
      array.each do |entity_hash|
        return entity_hash if _compare_hash(entity_hash, search_hash)
      end
      return nil
    end

    def last_in_cache?(entity_type, id)
      return get_cache(entity_type).size == 1 && get_cache(entity_type).first[0] == id
    end

    # Method for use when writing messages to user.
    #     > to_singular(:contentveiws)
    #     "contentview"
    #     > to_singular(:repositories)
    #     "repository"
    def to_singular(plural)
      return plural.to_s.gsub(/_/, ' ').sub(/s$/, '').sub(/ie$/, 'y')
    end

    def split_multival(multival, convert_to_int = true, separator = ';')
      arr = (multival || '').split(separator).delete_if { |v| v == 'None' }
      arr.map!(&:to_i) if convert_to_int
      return arr
    end

    # Method to call when you have created/deleted/found/mapped... something.
    # Collected data used for summary reporting.
    #
    # :found is used for situation, when you want to create something,
    # but you found out, it is already created.
    def report_summary(verb, item)
      raise "Not summary supported action: #{verb}" unless
        [:created, :deleted, :found, :mapped, :skipped, :uploaded, :wrote, :failed].include? verb
      @summary[verb] ||= {}
      @summary[verb][item] = @summary[verb].fetch(item, 0) + 1
    end

    def print_summary
      progress 'Summary'
      @summary.each do |verb, what|
        what.each do |entity, count|
          noun = if count == 1
                   to_singular entity
                 else
                   entity
                 end
          report = "  #{verb.to_s.capitalize} #{count} #{noun}."
          if verb == :found
            info report
          else
            progress report
          end
        end
      end
      progress '  No action taken.' if (@summary.keys - [:found]).empty?
    end

    def get_translated_id(entity_type, entity_id)
      if @pm[entity_type] && @pm[entity_type][entity_id]
        return @pm[entity_type][entity_id]
      end
      raise MissingObjectError, 'Unable to import, first import ' + to_singular(entity_type) + \
        ' with id ' + entity_id.inspect
    end

    # this method returns a *first* found original_id
    # (since we're able to map several organizations into one)
    def get_original_id(entity_type, import_id)
      if was_translated(entity_type, import_id)
        # find original_ids
        @pm[entity_type].to_hash.each do |key, value|
          return key if value == import_id
        end
      else
        debug "Unknown imported #{to_singular(entity_type)} [#{import_id}]."
      end
      return nil
    end

    def list_server_entities(entity_type, extra_hash = {}, use_cache = false)
      if @prerequisite[entity_type]
        list_server_entities(@prerequisite[entity_type]) unless @cache[@prerequisite[entity_type]]
      end

      @cache[entity_type] ||= {}
      results = []

      if !extra_hash.empty? || @prerequisite[entity_type].nil?
        if use_cache
          @list_cache ||= {}
          if @list_cache[entity_type]
            return @list_cache[entity_type][extra_hash] if @list_cache[entity_type][extra_hash]
          else
            @list_cache[entity_type] ||= {}
          end
        end
        entities = api_call(entity_type, :index, {'per_page' => 999999}.merge(extra_hash))
        results = entities['results']
        @list_cache[entity_type][extra_hash] = results if use_cache
      elsif @prerequisite[entity_type] == :organizations
        # check only entities in imported orgs (not all of them)
        @pm[:organizations].to_hash.values.each do |org_id|
          entities = api_call(entity_type, :index, {'per_page' => 999999, 'organization_id' => org_id})
          results += entities['results']
        end
      else
        @cache[@prerequisite[entity_type]].each do |pre_id, _|
          entities = api_call(
            entity_type,
            :index,
            {
              'per_page' => 999999,
              @prerequisite[entity_type].to_s.sub(/s$/, '_id').to_sym => pre_id
            })
          results += entities['results']
        end
      end

      results.each do |entity|
        entity['id'] = entity['id'].to_s if entity_type == :hosts
        @cache[entity_type][entity['id']] = entity
      end
    end

    def map_entity(entity_type, original_id, id)
      if @pm[entity_type][original_id]
        info "#{to_singular(entity_type).capitalize} [#{original_id}->#{@pm[entity_type][original_id]}] already mapped. " \
          'Skipping.'
        report_summary :found, entity_type
        return
      end
      info "Mapping #{to_singular(entity_type)} [#{original_id}->#{id}]."
      @pm[entity_type][original_id] = id
      report_summary :mapped, entity_type
      return get_cache(entity_type)[id]
    end

    def unmap_entity(entity_type, target_id)
      deleted = @pm[entity_type].delete_value(target_id)
      info " Unmapped #{to_singular(entity_type)} with id #{target_id}: #{deleted}x" if deleted > 1
    end

    def find_uniq(arr)
      uniq = nil
      uniq = arr[0] if arr[1].is_a?(Array) &&
                       (arr[1][0] =~ /has already been taken/ ||
                        arr[1][0] =~ /already exists/ ||
                        arr[1][0] =~ /must be unique within one organization/)
      return uniq
    end

    def found_errors(err)
      return err && err['errors'] && err['errors'].respond_to?(:each)
    end

    def recognizable_error(arr)
      return arr.is_a?(Array) && arr.size >= 2
    end

    def process_error(err, entity_hash)
      uniq = nil
      err['errors'].each do |arr|
        next unless recognizable_error(arr)
        uniq = find_uniq(arr)
        break if uniq && entity_hash.key?(uniq.to_sym)
        uniq = nil # otherwise uniq is not usable
      end
      return uniq
    end

    # Create entity, with recovery strategy.
    #
    # * +:map+ - Use existing entity
    # * +:rename+ - Change name
    # * +nil+ - Fail
    def create_entity(entity_type, entity_hash, original_id, recover = nil, retries = 2)
      raise ImportRecoveryError, "Creation of #{entity_type} not recovered by " \
        "'#{recover || option_recover.to_sym}' strategy" if retries < 0
      uniq = nil
      begin
        return _create_entity(entity_type, entity_hash, original_id)
      rescue RestClient::UnprocessableEntity => ue
        error " Creation of #{to_singular(entity_type)} failed."
        uniq = nil
        err = JSON.parse(ue.response)
        err = err['error'] if err.key?('error')
        if found_errors(err)
          uniq = process_error(err, entity_hash)
        end
        raise ue unless uniq
      end

      uniq = uniq.to_sym

      case recover || option_recover.to_sym
      when :rename
        entity_hash[uniq] = original_id.to_s + '-' + entity_hash[uniq]
        info " Recovering by renaming to: \"#{uniq}\"=\"#{entity_hash[uniq]}\""
        return create_entity(entity_type, entity_hash, original_id, recover, retries - 1)
      when :map
        entity = lookup_entity_in_cache(entity_type, {uniq.to_s => entity_hash[uniq]})
        if entity
          info " Recovering by remapping to: #{entity['id']}"
          return map_entity(entity_type, original_id, entity['id'])
        else
          warn "Creation of #{entity_type} not recovered by \'#{recover}\' strategy."
          raise ImportRecoveryError, "Creation of #{entity_type} not recovered by \'#{recover}\' strategy."
        end
      else
        fatal 'No recover strategy.'
        raise ue
      end
      nil
    end

    # Use +create_entity+ instead.
    def _create_entity(entity_type, entity_hash, original_id)
      type = to_singular(entity_type)
      if @pm[entity_type][original_id]
        info type.capitalize + ' [' + original_id.to_s + '->' + @pm[entity_type][original_id].to_s + '] already imported.'
        report_summary :found, entity_type
        return get_cache(entity_type)[@pm[entity_type][original_id]]
      else
        info 'Creating new ' + type + ': ' + entity_hash.values_at(:name, :label, :login).compact[0]
        if entity_type == :hosts
          entity = @api.resource(:host_subscriptions).call(:create, entity_hash)
          params = {
            'id' => entity['id'],
            'host' => {
              'comment' => entity_hash[:description]
            }
          }
          entity = @api.resource(:hosts).call(:update, params)
          unless entity_hash[:host_collection_ids].empty?
            @api.resource(:host_collections).call(:add_hosts, {
                'id' => entity_hash[:host_collection_ids][0],
                'host_ids' => [entity['id']]
            })
          end
          entity['id'] = entity['id'].to_s
        else
          entity_hash = {@wrap_out[entity_type] => entity_hash} if @wrap_out[entity_type]
          debug "entity_hash: #{entity_hash.inspect}"
          entity = mapped_api_call(entity_type, :create, entity_hash)
        end
        debug "created entity: #{entity.inspect}"
        entity = entity[@wrap_in[entity_type]] if @wrap_in[entity_type]
        @pm[entity_type][original_id] = entity['id']
        get_cache(entity_type)[entity['id']] = entity
        debug "@pm[#{entity_type}]: #{@pm[entity_type].inspect}"
        report_summary :created, entity_type
        return entity
      end
    end

    def update_entity(entity_type, id, entity_hash)
      info "Updating #{to_singular(entity_type)} with id: #{id}"
      mapped_api_call(entity_type, :update, {:id => id}.merge!(entity_hash))
    end

    # Delete entity by original (Sat5) id
    def delete_entity(entity_type, original_id)
      type = to_singular(entity_type)
      unless @pm[entity_type][original_id]
        error 'Unknown ' + type + ' to delete [' + original_id.to_s + '].'
        return nil
      end
      info 'Deleting imported ' + type + ' [' + original_id.to_s + '->' + @pm[entity_type][original_id].to_s + '].'
      begin
        mapped_api_call(entity_type, :destroy, {:id => @pm[entity_type][original_id]})
        # delete from cache
        get_cache(entity_type).delete(@pm[entity_type][original_id])
        # delete from pm
        unmap_entity(entity_type, @pm[entity_type][original_id])
        report_summary :deleted, entity_type
      rescue => e
        warn "Delete of #{to_singular(entity_type)} [#{original_id}] failed with #{e.class}: #{e.message}"
        report_summary :failed, entity_type
      end
    end

    # Delete entity by target (Sat6) id
    def delete_entity_by_import_id(entity_type, import_id, delete_key = 'id')
      type = to_singular(entity_type)
      original_id = get_original_id(entity_type, import_id)
      if original_id.nil?
        error 'Unknown imported ' + type + ' to delete [' + import_id.to_s + '].'
        return nil
      end
      info "Deleting imported #{type} [#{original_id}->#{@pm[entity_type][original_id]}]."
      if delete_key == 'id'
        delete_id = import_id
      else
        delete_id = get_cache(entity_type)[import_id][delete_key]
      end
      begin
        mapped_api_call(entity_type, :destroy, {:id => delete_id})
        # delete from cache
        get_cache(entity_type).delete(import_id)
        # delete from pm
        @pm[entity_type].delete original_id
        report_summary :deleted, entity_type
      rescue => e
        warn "Delete of #{to_singular(entity_type)} [#{delete_id}] failed with #{e.class}: #{e.message}"
        report_summary :failed, entity_type
      end
    end

    # Wait for asynchronous task.
    #
    # * +uuid+ - UUID of async task.
    # * +start_wait+ - Seconds to wait before first check.
    # * +delta_wait+ - How much longer will every next wait be (unless +max_wait+ is reached).
    # * +max_wait+ - Maximum time to wait between two checks.
    def wait_for_task(uuid, start_wait = 0, delta_wait = 1, max_wait = 10)
      wait_time = start_wait
      if option_quiet?
        info "Waiting for the task [#{uuid}] "
      else
        print "Waiting for the task [#{uuid}] "
      end

      loop do
        sleep wait_time
        wait_time = [wait_time + delta_wait, max_wait].min
        print '.' unless option_quiet?
        STDOUT.flush unless option_quiet?
        task = api_call(:foreman_tasks, :show, {:id => uuid})
        next unless task['state'] == 'stopped'
        print "\n" unless option_quiet?
        return task['return'] == 'success'
      end
    end

    def cvs_iterate(filename, action)
      CSVHelper.csv_each filename, self.class.csv_columns do |data|
        handle_missing_and_supress "processing CSV line:\n#{data.inspect}" do
          action.call(data)
        end
      end
    end

    def import(filename)
      cvs_iterate(filename, (method :import_single_row))
    end

    def post_import(_csv_file)
      # empty by default
    end

    def post_delete(_csv_file)
      # empty by default
    end

    def delete(filename)
      cvs_iterate(filename, (method :delete_single_row))
    end

    def execute
      # Get set up to do logging as soon as reasonably possible
      setup_logging
      # create a storage directory if not exists yet
      Dir.mkdir data_dir unless File.directory? data_dir

      # initialize apipie binding
      self.class.api_init
      load_persistent_maps
      load_cache
      prune_persistent_maps @cache
      # TODO: This big ugly thing might need some cleanup
      begin
        if option_delete?
          info "Deleting from #{option_csv_file}"
          delete option_csv_file
          handle_missing_and_supress 'post_delete' do
            post_delete option_csv_file
          end
        else
          info "Importing from #{option_csv_file}"
          import option_csv_file
          handle_missing_and_supress 'post_import' do
            post_import option_csv_file
          end
        end
        atr_exit
      rescue StandardError, SystemExit, Interrupt => e
        error "Exiting: #{e}"
        logtrace e
      end
      save_persistent_maps
      print_summary
      HammerCLI::EX_OK
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
