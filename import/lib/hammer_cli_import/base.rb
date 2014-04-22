# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
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
      @wrap_in = {:organizations => "organization"}
      # persistent maps to store translated object ids
      @per_org = {:system_groups => true, :repositories => true, :products => true}
      @pm = {}
      # cache imported objects (created/lookuped)
      @cache = {}
      # apipie binding
      @api = nil
    end

    option ['--csv-file'], 'FILE_NAME', 'CSV file', :required => true
    option ['--delete'], :flag, 'Delete entities from CSV file'
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
      File.join(File.expand_path("~"), "data")
    end

    class << self
      attr_reader :maps
    end

    def self.persistent_maps(*list)
      @maps = list
    end

    def load_maps()
      self.class.maps.each do |map_sym|
        hash = {}
        @cache[map_sym] = {}
        Dir[File.join data_dir, "#{map_sym}-*.csv"].sort.each do |filename|
          reader = CSV.open(filename, 'r')
          header = reader.shift
          raise PersistentMapError, "Importing :#{map_sym} from file #{filename}" unless header == ['sat5', 'sat6']
          reader.each do |row|
            hash[row[0].to_i] = row[1].to_i
          end
        end
        @pm[map_sym] = DeltaHash[hash]
      end
    end

    def verify_maps()
      @pm.keys.each do |map_sym|
        unless @pm[map_sym].to_hash.empty?
          entities = list_entities map_sym
          entity_ids = entities.map { |e| e["id"].to_i }
          extra = @pm[map_sym].to_hash.values - entity_ids
          unless extra.empty?
            puts "Removing " + map_sym.to_s + " from persistent map: " + extra.join(" ")
            @pm[map_sym].delete_if { |key, value| extra.include?(value) }
          end
        end
      end
    end

    def save_maps
      self.class.maps.each do |map_sym|
        next if @pm[map_sym].new.empty?
        CSV.open((File.join data_dir, "#{map_sym}-#{Time.now.utc.iso8601}.csv"), "wb", {:force_quotes => true}) do |csv|
          csv << ['sat5', 'sat6']
          @pm[map_sym].new.each do |key, value|
            csv << [key, value]
          end
        end
      end
    end
    ## <-
    ############

    def import_single_row(row)
    end

    def lookup_entity(entity_type, entity_id)
      unless (@cache[entity_type][entity_id])
        @cache[entity_type][entity_id] = @api.resource(entity_type).call(:show, {"id" => entity_id})
      else
        puts "#{to_singular(entity_type).capitalize} #{entity_id} taken from cache."
      end
      return @cache[entity_type][entity_id]
    end

    def to_singular(plural)
      return plural.to_s.sub(/s$/, "").sub(/ie$/,"y")
    end

    def get_translated_id(entity_type, entity_id)
      if @pm[entity_type] and @pm[entity_type][entity_id.to_i]
        return @pm[entity_type][entity_id.to_i]
      end
      raise MissingObjectError, "Need to import " + to_singular(entity_type) + " with id " + entity_id.to_s
    end

    def list_entities(entity_type)
      if @per_org[entity_type]
        results = []
        # check only entities in imported orgs (not all of them)
        @pm[:organizations].to_hash.values.each do |org_id|
          org_identifier = lookup_entity(:organizations, org_id)["label"]
          p org_identifier
          entities = @api.resource(entity_type).call(:index, {'per_page' => 999999, 'organization_id' => org_identifier})
          results += entities["results"]
        end
        return results
      else
        entities = @api.resource(entity_type).call(:index, {'per_page' => 999999})
        return entities["results"]
      end
    end

    def create_entity(entity_type, entity_hash, original_id)
      type = to_singular(entity_type)
      if @pm[entity_type][original_id]
        puts type.capitalize + " [" + original_id.to_s + "->" + @pm[entity_type][original_id].to_s + "] already imported."
        return @cache[entity_type][@pm[entity_type][original_id]]
      else
        puts "Creating new " + type + ": " + entity_hash.values_at(:name, :label, :login).compact[0]
        entity_hash = {@wrap_out[entity_type] => entity_hash} if @wrap_out[entity_type]
        begin
          entity = @api.resource(entity_type).call(:create, entity_hash)
          p "created entity:", entity
          entity = entity[@wrap_in[entity_type]] if @wrap_in[entity_type]
          @pm[entity_type][original_id] = entity["id"]
          @cache[entity_type][entity["id"]] = entity
          p "@pm[entity_type]:", @pm[entity_type]
        rescue Exception => e
          puts "Creation of #{type} failed with #{e.inspect}"
        end
        return entity
      end
    end

    def import(filename)
      reader = CSV.open(filename, 'r')
      header = reader.shift
      self.class.csv_columns.each do |col|
        raise CSVHeaderError, "column #{col} expected in #{filename}" unless header.include? col
      end
      reader.each do |row|
        import_single_row(Hash[header.zip row])
      end
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
      import option_csv_file
      save_maps
      HammerCLI::EX_OK
    end
  end
end

