# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'csv'

require 'apipie-bindings'
require 'hammer_cli'

module HammerCLIImport
  class MissingObjectError < RuntimeError
  end

  class BaseCommand < HammerCLI::Apipie::Command
    extend PersistentMap::Extend
    include PersistentMap::Include

    def initialize(*list)
      super(*list)
      # wrap API parameters into extra hash
      @wrap_out = {:users => :user}
      # APIs return objects encapsulated in extra hash
      @wrap_in = {:organizations => 'organization'}
      # entities that needs organization to be listed
      @per_org = {
        :host_collections => true,
        :repositories => true,
        :products => true,
        :content_views => true,
        :activation_keys => true}
      # cache imported objects (created/lookuped)
      @cache = {}
      # apipie binding
      @api = nil
    end

    option ['--csv-file'], 'FILE_NAME', 'CSV file', :required => true
    option ['--delete'], :flag, 'Delete entities from CSV file', :default => false
    option ['--verify'], :flag, 'Verify entities from CSV file'

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

    def verify_maps
      @pm.keys.each do |map_sym|
        entities = list_entities map_sym
        entity_ids = entities.collect { |e| e['id'].to_i }
        extra = @pm[map_sym].to_hash.values - entity_ids
        unless extra.empty?
          puts 'Removing ' + map_sym.to_s + ' from persistent map: ' + extra.join(' ')
          @pm[map_sym].to_hash.each do |key, value|
            @pm[map_sym].delete key if extra.include? value
          end
        end
      end
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

    def to_singular(plural)
      return plural.to_s.sub(/s$/, '').sub(/ie$/, 'y')
    end

    def get_translated_id(entity_type, entity_id)
      if @pm[entity_type] && @pm[entity_type][entity_id.to_i]
        return @pm[entity_type][entity_id.to_i]
      end
      raise MissingObjectError, 'Need to import ' + to_singular(entity_type) + ' with id ' + entity_id.to_s
    end

    def list_entities(entity_type)
      if @per_org[entity_type]
        results = []
        # check only entities in imported orgs (not all of them)
        @pm[:organizations].to_hash.values.each do |org_id|
          entities = api_mapped_resource(entity_type).call(:index, {'per_page' => 999999, 'organization_id' => org_id})
          entities['results'].each do |entity|
            get_cache(entity_type)[entity['id']] = entity
          end
          results += entities['results']
        end
        return results
      else
        entities = api_mapped_resource(entity_type).call(:index, {'per_page' => 999999})
        entities['results'].each do |entity|
          get_cache(entity_type)[entity['id']] = entity
        end
        return entities['results']
      end
    end

    def create_entity(entity_type, entity_hash, original_id)
      type = to_singular(entity_type)
      if @pm[entity_type][original_id]
        puts type.capitalize + ' [' + original_id.to_s + '->' + @pm[entity_type][original_id].to_s + '] already imported.'
        return get_cache(entity_type)[@pm[entity_type][original_id]]
      else
        puts 'Creating new ' + type + ': ' + entity_hash.values_at(:name, :label, :login).compact[0]
        entity_hash = {@wrap_out[entity_type] => entity_hash} if @wrap_out[entity_type]
        begin
          entity = api_mapped_resource(entity_type).call(:create, entity_hash)
          # p "created entity:", entity
          entity = entity[@wrap_in[entity_type]] if @wrap_in[entity_type]
          @pm[entity_type][original_id] = entity['id']
          get_cache(entity_type)[entity['id']] = entity
          # p "@pm[entity_type]:", @pm[entity_type]
        rescue StandardError => e
          puts "Creation of #{type} failed with #{e.inspect}"
        end
        return entity
      end
    end

    def update_entity(entity_type, id, entity_hash)
      puts 'Updating ' + to_singular(entity_type) + ' with id: ' + id.to_s
      api_mapped_resource(entity_type).call(:update, {:id => id}.merge!(entity_hash))
    end

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
      @pm[entity_type].delete original_id
    end

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
      puts 'Deleting imported ' + type + ' [' + original_id.to_s + '->' + @pm[entity_type][original_id].to_s + '].'
      api_mapped_resource(entity_type).call(:destroy, {:id => import_id})
      # delete from cache
      get_cache(entity_type).delete(import_id)
      # delete from pm
      @pm[entity_type].delete original_id
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
        :api_version => 2
      })
      load_persistent_maps do |map_sym|
        @cache[map_sym] = {}
      end
      verify_maps
      if option_delete?
        delete option_csv_file
      else
        import option_csv_file
        post_import option_csv_file
      end
      save_persistent_maps
      HammerCLI::EX_OK
    end
  end
end
