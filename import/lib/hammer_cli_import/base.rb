# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'csv'

require 'apipie-bindings'
require 'hammer_cli'

module HammerCLIImport
  class PersistentMapError < RuntimeError
  end

  class CSVHeaderError < RuntimeError
  end

  class MissingObjectError < RuntimeError
  end

  class BaseCommand < HammerCLI::Apipie::Command
    def initialize(*list)
      super(*list)
      # wrap API parameters into extra hash
      @wrap_out = {:users => :user}
      # APIs return objects encapsulated in extra hash
      @wrap_in = {:organizations => 'organization'}
      # persistent maps to store translated object ids
      @per_org = {:system_groups => true, :repositories => true, :products => true}
      @pm = {}
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
        raise RuntimeError, 'set more than once' if @csv_columns
        @csv_columns = list
      end
    end
    ## <-
    ############

    ############
    ## -> Stuff related to persistent maps (of ID-s?)
    def data_dir
      File.join(File.expand_path('~'), 'data')
    end

    class << self
      attr_reader :maps, :map_description

      def persistent_map(symbol, key_spec, val_spec)
        @maps ||= []
        @maps.push symbol
        @map_description ||= {}
        @map_description[symbol] = [key_spec, val_spec]
      end

      def persistent_maps(*list)
        list.each do |sym|
          persistent_map sym, [{'sat5' => Fixnum}], [{'sat6' => Fixnum}]
        end
      end
    end

    def pm_csv_headers(symbol)
      key_spec, val_spec = self.class.map_description[symbol]
      (key_spec + val_spec).collect { |x| x.keys[0] }
    end

    class << Fixnum
      def from_s(x)
        x.to_i
      end
    end

    class << String
      def from_s(x)
        x
      end
    end

    def pm_decode_row(symbol, row)
      key_spec, val_spec = self.class.map_description[symbol]
      key = []
      value = []

      key_spec.each do |spec|
        x = row.shift
        key.push(spec.values.first.from_s x)
      end

      val_spec.each do |spec|
        x = row.shift
        value.push(spec.values.first.from_s x)
      end

      key = key[0] if key.size == 1
      value = value[0] if value.size == 1
      [key, value]
    end

    def load_maps()
      self.class.maps.each do |map_sym|
        hash = {}
        @cache[map_sym] = {}
        Dir[File.join data_dir, "#{map_sym}-*.csv"].sort.each do |filename|
          reader = CSV.open(filename, 'r')
          header = reader.shift
          raise PersistentMapError, "Importing :#{map_sym} from file #{filename}" unless header == (pm_csv_headers map_sym)
          reader.each do |row|
            key, value = pm_decode_row map_sym, row
            hash[key] = value
          end
        end
        @pm[map_sym] = DeltaHash[hash]
      end
    end

    def verify_maps()
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

    def save_maps
      self.class.maps.each do |map_sym|
        next if @pm[map_sym].new.empty?
        CSV.open((File.join data_dir, "#{map_sym}-#{Time.now.utc.iso8601}.csv"), 'wb') do |csv|
          csv << (pm_csv_headers map_sym)
          @pm[map_sym].new.each do |key, value|
            key = [key] unless key.is_a? Array
            value = [value] unless value.is_a? Array
            csv << key + value
          end
        end
      end
    end
    ## <-
    ############

    def import_single_row(_row)
      puts 'Import not implemented.'
    end

    def delete_single_row(_row)
      puts 'Delete not implemented.'
    end

    def lookup_entity(entity_type, entity_id, online_lookup = false)
      if (! @cache[entity_type][entity_id] or online_lookup)
        @cache[entity_type][entity_id] = @api.resource(entity_type).call(:show, {'id' => entity_id})
      else
        # puts "#{to_singular(entity_type).capitalize} #{entity_id} taken from cache."
      end
      return @cache[entity_type][entity_id]
    end

    def to_singular(plural)
      return plural.to_s.sub(/s$/, '').sub(/ie$/,'y')
    end

    def get_translated_id(entity_type, entity_id)
      if @pm[entity_type] and @pm[entity_type][entity_id.to_i]
        return @pm[entity_type][entity_id.to_i]
      end
      raise MissingObjectError, 'Need to import ' + to_singular(entity_type) + ' with id ' + entity_id.to_s
    end

    def list_entities(entity_type)
      if @per_org[entity_type]
        results = []
        # check only entities in imported orgs (not all of them)
        @pm[:organizations].to_hash.values.each do |org_id|
          org_identifier = lookup_entity(:organizations, org_id)['label']
          entities = @api.resource(entity_type).call(:index, {'per_page' => 999999, 'organization_id' => org_identifier})
          entities['results'].each do |entity|
            @cache[entity_type][entity['id']] = entity
          end
          results += entities['results']
        end
        return results
      else
        entities = @api.resource(entity_type).call(:index, {'per_page' => 999999})
        entities['results'].each do |entity|
          @cache[entity_type][entity['id']] = entity
        end
        return entities['results']
      end
    end

    def create_entity(entity_type, entity_hash, original_id)
      type = to_singular(entity_type)
      if @pm[entity_type][original_id]
        puts type.capitalize + ' [' + original_id.to_s + '->' + @pm[entity_type][original_id].to_s + '] already imported.'
        return @cache[entity_type][@pm[entity_type][original_id]]
      else
        puts 'Creating new ' + type + ': ' + entity_hash.values_at(:name, :label, :login).compact[0]
        entity_hash = {@wrap_out[entity_type] => entity_hash} if @wrap_out[entity_type]
        begin
          entity = @api.resource(entity_type).call(:create, entity_hash)
          # p "created entity:", entity
          entity = entity[@wrap_in[entity_type]] if @wrap_in[entity_type]
          @pm[entity_type][original_id] = entity['id']
          @cache[entity_type][entity['id']] = entity
          # p "@pm[entity_type]:", @pm[entity_type]
        rescue Exception => e
          puts "Creation of #{type} failed with #{e.inspect}"
        end
        return entity
      end
    end

    def update_entity(entity_type, id, entity_hash)
      puts 'Updating ' + to_singular(entity_type) + ' with id: ' + id.to_s
      @api.resource(entity_type).call(:update, {:id => id}.merge!(entity_hash))
    end

    def delete_entity(entity_type, original_id)
      type = to_singular(entity_type)
      unless @pm[entity_type][original_id]
        puts 'Unknown ' + type + ' to delete [' + original_id.to_s + '].'
        return nil
      end
      puts 'Deleting imported ' + type + ' [' + original_id.to_s + '->' + @pm[entity_type][original_id].to_s + '].'
      @api.resource(entity_type).call(:destroy, {:id => @pm[entity_type][original_id]})
      # delete from cache
      @cache[entity_type].delete(@pm[entity_type][original_id])
      # delete from pm
      @pm[entity_type].delete original_id
    end

    def delete_entity_by_import_id(entity_type, import_id)
      original_id = nil
      type = to_singular(entity_type)
      unless @pm[entity_type].to_hash.values.include?(import_id)
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
      @api.resource(entity_type).call(:destroy, {:id => import_id})
      # delete from cache
      @cache[entity_type].delete(import_id)
      # delete from pm
      @pm[entity_type].delete original_id
    end

    def cvs_iterate(filename, action)
      reader = CSV.open(filename, 'r')
      header = reader.shift
      self.class.csv_columns.each do |col|
        raise CSVHeaderError, "column #{col} expected in #{filename}" unless header.include? col
      end
      reader.each do |row|
        action.call(Hash[header.zip row])
      end
    end

    def import(filename)
      cvs_iterate(filename, (method :import_single_row))
    end

    def delete(filename)
      cvs_iterate(filename, (method :delete_single_row))
    end

    def execute
      # create a storage directory if not exists yet
      Dir.mkdir data_dir unless File.directory? data_dir

      # initialize apipie binding
      @api = ApipieBindings::API.new({
        :uri => HammerCLI::Settings.get(:foreman, :host),
        :username => HammerCLI::Settings.get(:foreman, :username),
        :password => HammerCLI::Settings.get(:foreman, :password),
        :api_version => 2
      })
      load_maps
      verify_maps
      if option_delete?
        delete option_csv_file
      else
        import option_csv_file
      end
      save_maps
      HammerCLI::EX_OK
    end
  end
end
