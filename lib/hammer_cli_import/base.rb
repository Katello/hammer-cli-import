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
    include PersistentMap::Include

    def initialize(*list)
      super(*list)
      # wrap API parameters into extra hash
      @wrap_out = {
        :users => :user,
        :template_snippets => :config_template
      }
      # APIs return objects encapsulated in extra hash
      @wrap_in = {:organizations => 'organization'}
      # entities that needs organization to be listed
      @prerequisite = {
        :activation_keys => :organizations,
        :content_views => :organizations,
        :content_view_versions => :organizations,
        :host_collections => :organizations,
        :products => :organizations,
        :repositories => :organizations,
        :repository_sets => :products
        :users => :organizations,
      }
      # cache imported objects (created/lookuped)
      @cache = {}
      class << @cache
        def []=(key, val)
          fail "@cache: #{val.inspect} is not a hash!" unless val.is_a? Hash
          super
        end
      end
    end

    option ['--csv-file'], 'FILE_NAME', 'CSV file', :required => true do |filename|
      raise ArgumentError, "File #{filename} does not exist" unless File.exist? filename
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
        @api ||= ApipieBindings::API.new(
        {
          :uri => HammerCLI::Settings.get(:foreman, :host),
          :username => HammerCLI::Settings.get(:foreman, :username),
          :password => HammerCLI::Settings.get(:foreman, :password),
          :api_version => 2,
          :logger => Logger.new('/dev/null')
        })
        nil
      end

      # Call API. Ideally accessed via +api_call+ instance method.
      # This is supposed to be the only way to access @api.
      def api_call(resource, action, params = {}, debug = false)
        @api.resource(resource).call(action, params)
      rescue
        puts "Error on api.resource(#{resource}).call(#{action}, #{params}):" if debug
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
      File.join(File.expand_path('~'), 'data')
    end

    # This method is called to process single CSV line when
    # importing.
    def import_single_row(_row)
      puts 'Import not implemented.'
    end

    # This method is called to process single CSV line when
    # deleting
    def delete_single_row(_row)
      puts 'Delete not implemented.'
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
        # puts "#{to_singular(entity_type).capitalize} #{entity_id} taken from cache."
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

    def last_in_cache?(entity_type, id)
      return get_cache(entity_type).size == 1 && get_cache(entity_type).first[0] == id
    end

    # Method for use when writing messages to user.
    #     > to_singular(:contentveiws)
    #     "contentview"
    #     > to_singular(:repositories)
    #     "repository"
    def to_singular(plural)
      return plural.to_s.sub(/s$/, '').sub(/ie$/, 'y')
    end

    def split_multival(multival, convert_to_int = true, separator = ';')
      arr = (multival || '').split(separator).delete_if { |v| v == 'None' }
      arr.map! { |x| x.to_i } if convert_to_int
      return arr
    end

    def get_translated_id(entity_type, entity_id)
      if @pm[entity_type] && @pm[entity_type][entity_id]
        return @pm[entity_type][entity_id]
      end
      raise MissingObjectError, 'Need to import ' + to_singular(entity_type) + ' with id ' + entity_id.to_s
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
        # puts 'Unknown imported ' + to_singular(entity_type) + ' [' + import_id.to_s + '].'
      end
      return nil
    end

    def list_server_entities(entity_type, extra_hash = {})
      if @prerequisite[entity_type]
        list_server_entities(@prerequisite[entity_type]) unless @cache[@prerequisite[entity_type]]
      end

      @cache[entity_type] ||= {}
      results = []

      if !extra_hash.empty? || entity_type == :organizations
        entities = api_call(entity_type, :index, {'per_page' => 999999}.merge(extra_hash))
        results = entities['results']
      elsif @prerequisite[entity_type] == :organizations
        # check only entities in imported orgs (not all of them)
        @pm[:organizations].to_hash.values.each do |org_id|
          entities = api_call(entity_type, :index, {'per_page' => 999999, 'organization_id' => org_id})
          results += entities['results']
        end
      elsif @prerequisite[entity_type]
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
        @cache[entity_type][entity['id']] = entity
      end
    end

    def map_entity(entity_type, original_id, id)
      if @pm[entity_type][original_id]
        puts "#{to_singular(entity_type).capitalize} [#{original_id}->#{@pm[entity_type][original_id]}] already mapped. " + \
        'Skipping.'
        return
      end
      puts "Mapping #{to_singular(entity_type)} [#{original_id}->#{id}]."
      @pm[entity_type][original_id] = id
    end

    def unmap_entity(entity_type, target_id)
      deleted = @pm[entity_type].delete_value(target_id)
      puts " Unmapped #{to_singular(entity_type)} with id #{target_id}: #{deleted}x" if deleted > 1
    end

    # Create entity, with recovery strategy.
    #
    # * +:map+ - Use existing entity
    # * +:rename+ - Change name
    # * +nil+ - Fail
    def create_entity(entity_type, entity_hash, original_id, recover = nil, retries = 2)
      raise ImportRecoveryError, "Creation of #{entity_type} not recovered by \'#{recover}\' strategy." if retries < 0
      begin
        return _create_entity(entity_type, entity_hash, original_id)
      rescue RestClient::UnprocessableEntity => ue
        puts " Creation of #{to_singular(entity_type)} failed."
        errs = JSON.parse(ue.response)['errors']
        uniq = errs.first[0] if errs.first[1].is_a?(Array) && errs.first[1][0] =~ /must be unique/

        raise ue unless uniq
      end

      uniq = uniq.to_sym unless entity_hash[uniq]

      case recover || option_recover.to_sym
      when :rename
        entity_hash[uniq] = original_id.to_s + '-' + entity_hash[uniq]
        puts " Recovering by renaming to: \"#{uniq}\"=\"#{entity_hash[uniq]}\""
        return create_entity(entity_type, entity_hash, original_id, recover, retries - 1)
      when :map
        entity = lookup_entity_in_cache(entity_type, {uniq.to_s => entity_hash[uniq]})
        if entity
          puts " Recovering by remapping to: #{entity['id']}"
          map_entity(entity_type, original_id, entity['id'])
        else
          raise ImportRecoveryError, "Creation of #{entity_type} not recovered by \'#{recover}\' strategy."
        end
      else
        p 'No recover strategy.'
        raise ue
      end
      nil
    end

    # Use +create_entity+ instead.
    def _create_entity(entity_type, entity_hash, original_id)
      type = to_singular(entity_type)
      if @pm[entity_type][original_id]
        puts type.capitalize + ' [' + original_id.to_s + '->' + @pm[entity_type][original_id].to_s + '] already imported.'
        return get_cache(entity_type)[@pm[entity_type][original_id]]
      else
        puts 'Creating new ' + type + ': ' + entity_hash.values_at(:name, :label, :login).compact[0]
        entity_hash = {@wrap_out[entity_type] => entity_hash} if @wrap_out[entity_type]
        # p 'entity_hash:', entity_hash
        entity = mapped_api_call(entity_type, :create, entity_hash)
        # p 'created entity:', entity
        entity = entity[@wrap_in[entity_type]] if @wrap_in[entity_type]
        @pm[entity_type][original_id] = entity['id']
        get_cache(entity_type)[entity['id']] = entity
        # p "@pm[entity_type]:", @pm[entity_type]
        return entity
      end
    end

    def update_entity(entity_type, id, entity_hash)
      puts "Updating #{to_singular(entity_type)} with id: #{id}"
      mapped_api_call(entity_type, :update, {:id => id}.merge!(entity_hash))
    end

    # Delete entity by original (Sat5) id
    def delete_entity(entity_type, original_id)
      type = to_singular(entity_type)
      unless @pm[entity_type][original_id]
        puts 'Unknown ' + type + ' to delete [' + original_id.to_s + '].'
        return nil
      end
      puts 'Deleting imported ' + type + ' [' + original_id.to_s + '->' + @pm[entity_type][original_id].to_s + '].'
      mapped_api_call(entity_type, :destroy, {:id => @pm[entity_type][original_id]})
      # delete from cache
      get_cache(entity_type).delete(@pm[entity_type][original_id])
      # delete from pm
      unmap_entity(entity_type, @pm[entity_type][original_id])
    end

    # Delete entity by target (Sat6) id
    def delete_entity_by_import_id(entity_type, import_id)
      type = to_singular(entity_type)
      original_id = get_original_id(entity_type, import_id)
      if original_id.nil?
        puts 'Unknown imported ' + type + ' to delete [' + import_id.to_s + '].'
        return nil
      end
      puts "Deleting imported #{type} [#{original_id}->#{@pm[entity_type][original_id]}]."
      mapped_api_call(entity_type, :destroy, {:id => import_id})
      # delete from cache
      get_cache(entity_type).delete(import_id)
      # delete from pm
      @pm[entity_type].delete original_id
    end

    # Wait for asynchronous task.
    #
    # * +uuid+ - UUID of async task.
    # * +start_wait+ - Seconds to wait before first check.
    # * +delta_wait+ - How much longer will every next wait be (unless +max_wait+ is reached).
    # * +max_wait+ - Maximum time to wait between two checks.
    def wait_for_task(uuid, start_wait = 0, delta_wait = 1, max_wait = 10)
      wait_time = start_wait
      print "Waiting for the task [#{uuid}] "
      loop do
        sleep wait_time
        wait_time = [wait_time + delta_wait, max_wait].min
        print '.'
        STDOUT.flush
        task = api_call(:foreman_tasks, :show, {:id => uuid})
        next unless task['state'] == 'stopped'
        print "\n"
        return task['return'] == 'success'
      end
    end

    def cvs_iterate(filename, action)
      CSVHelper.csv_each filename, self.class.csv_columns do |data|
        begin
          action.call(data)
        rescue => e
          puts "Caught #{e.class}:#{e.message} while processing following line:"
          p data
          puts e.backtrace.join "\n"
        end
      end
    end

    def import(filename)
      cvs_iterate(filename, (method :import_single_row))
    end

    def post_import(_csv_file)
      # empty by default
    end

    def delete(filename)
      cvs_iterate(filename, (method :delete_single_row))
    end

    def execute
      # create a storage directory if not exists yet
      Dir.mkdir data_dir unless File.directory? data_dir

      # initialize apipie binding
      self.class.api_init
      load_persistent_maps
      load_cache
      prune_persistent_maps @cache
      if option_delete?
        delete option_csv_file
      else
        import option_csv_file
        begin
          post_import option_csv_file
        rescue => e
          puts "Caught #{e.class}:#{e.message} while post_import"
          puts e.backtrace.join "\n"
        end
      end
      save_persistent_maps
      HammerCLI::EX_OK
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
