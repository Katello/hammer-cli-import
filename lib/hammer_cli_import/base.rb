# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
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
      @per_org = Set[
        :host_collections,
        :repositories,
        :products,
        :content_views,
        :activation_keys,
        :content_view_versions]
      # cache imported objects (created/lookuped)
      @cache = {}
      # apipie binding
      @api = nil
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

    ############
    ## -> Stuff related to csv columns
    class << self
      def csv_columns(*list)
        return @csv_columns if list.empty?
        raise 'set more than once' if @csv_columns
        @csv_columns = list
      end
    end
    ## <-
    ############

    def data_dir
      File.join(File.expand_path('~'), 'data')
    end

    def import_single_row(_row)
      puts 'Import not implemented.'
    end

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

    def api_mapped_resource(entity_type)
      @api.resource(map_target_entity[entity_type])
    end

    def lookup_entity(entity_type, entity_id, online_lookup = false)
      if (!get_cache(entity_type)[entity_id] || online_lookup)
        get_cache(entity_type)[entity_id] = api_mapped_resource(entity_type).call(:show, {'id' => entity_id})
      else
        # puts "#{to_singular(entity_type).capitalize} #{entity_id} taken from cache."
      end
      return get_cache(entity_type)[entity_id]
    end

    def was_translated(entity_type, import_id)
      return @pm[entity_type].to_hash.value?(import_id)
    end

    def lookup_entity_in_cache(entity_type, search_hash)
      get_cache(entity_type).each do |_entity_id, entity|
        return entity if entity.merge(search_hash) == entity
      end
      return nil
    end

    def last_in_cache?(entity_type, id)
      return get_cache(entity_type).size == 1 && get_cache(entity_type).first[0] == id
    end

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

    def list_server_entities(entity_type, extra_hash = {})
      @cache[entity_type] ||= {}
      if extra_hash.empty? && @per_org.include?(entity_type)
        results = []
        # check only entities in imported orgs (not all of them)
        @pm[:organizations].to_hash.values.each do |org_id|
          entities = @api.resource(entity_type).call(:index, {'per_page' => 999999, 'organization_id' => org_id})
          results += entities['results']
        end
      else
        entities = @api.resource(entity_type).call(:index, {'per_page' => 999999}.merge(extra_hash))
        results =  entities['results']
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

    def create_entity(entity_type, entity_hash, original_id, recover = nil, retries = 2)
      raise ImportRecoveryError, "Creation of #{entity_type} not recovered by \'#{recover}\' strategy." if retries < 0
      begin
        return _create_entity(entity_type, entity_hash, original_id)
      rescue RestClient::UnprocessableEntity => ue
        puts " Creation of #{to_singular(entity_type)} failed."
        errs = JSON.parse(ue.response)['errors']
        uniq = errs.first[0] if errs.first[1].kind_of?(Array) && errs.first[1][0] =~ /must be unique/

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

    def _create_entity(entity_type, entity_hash, original_id)
      type = to_singular(entity_type)
      if @pm[entity_type][original_id]
        puts type.capitalize + ' [' + original_id.to_s + '->' + @pm[entity_type][original_id].to_s + '] already imported.'
        return get_cache(entity_type)[@pm[entity_type][original_id]]
      else
        puts 'Creating new ' + type + ': ' + entity_hash.values_at(:name, :label, :login).compact[0]
        entity_hash = {@wrap_out[entity_type] => entity_hash} if @wrap_out[entity_type]
        # p 'entity_hash:', entity_hash
        entity = api_mapped_resource(entity_type).call(:create, entity_hash)
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
      api_mapped_resource(entity_type).call(:update, {:id => id}.merge!(entity_hash))
    end

    # Delete entity by original (Sat5) id
    def delete_entity(entity_type, original_id)
      type = to_singular(entity_type)
      unless @pm[entity_type][original_id]
        puts 'Unknown ' + type + ' to delete [' + original_id.to_s + '].'
        return nil
      end
      puts 'Deleting imported ' + type + ' [' + original_id.to_s + '->' + @pm[entity_type][original_id].to_s + '].'
      api_mapped_resource(entity_type).call(:destroy, {:id => @pm[entity_type][original_id]})
      # delete from cache
      get_cache(entity_type).delete(@pm[entity_type][original_id])
      # delete from pm
      unmap_entity(entity_type, @pm[entity_type][original_id])
    end

    # Delete entity by target (Sat6) id
    def delete_entity_by_import_id(entity_type, import_id)
      original_id = nil
      type = to_singular(entity_type)
      if ! @pm[entity_type].to_hash.values.include?(import_id)
        puts 'Unknown imported ' + type + ' to delete [' + import_id.to_s + '].'
        return nil
      else
        # find original_id
        @pm[entity_type].to_hash.each do |key, value|
          original_id = key if value == import_id
        end
        original_id = '?' unless original_id
      end
      puts "Deleting imported #{type} [#{original_id}->#{@pm[entity_type][original_id]}]."
      api_mapped_resource(entity_type).call(:destroy, {:id => import_id})
      # delete from cache
      get_cache(entity_type).delete(import_id)
      # delete from pm
      @pm[entity_type].delete original_id
    end

    def wait_for_task(uuid, start_wait = 0, delta_wait = 1, max_wait = 10)
      wait_time = start_wait
      print "Waiting for the task [#{uuid}] "
      loop do
        sleep wait_time
        wait_time = [wait_time + delta_wait, max_wait].min
        print '.'
        STDOUT.flush
        task = @api.resource(:foreman_tasks).call(:show, {:id => uuid})
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
      @api = ApipieBindings::API.new(
      {
        :uri => HammerCLI::Settings.get(:foreman, :host),
        :username => HammerCLI::Settings.get(:foreman, :username),
        :password => HammerCLI::Settings.get(:foreman, :password),
        :api_version => 2,
        :logger => Logger.new('/dev/null')
      })
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
