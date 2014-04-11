# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'apipie-bindings'
require 'hammer_cli'

module HammerCLIImport

  class PersistentMapError < RuntimeError
  end

  class CSVHeaderError < RuntimeError
  end

  class BaseCommand < HammerCLI::Apipie::Command

    option ['--csv-file'], 'FILE_NAME', 'CSV file', :required => true
    option ['--delete'], :flag, 'Delete entities from CSV file'
    option ['--verify'], :flag, 'Verify entities from CSV file'

    ############
    ## -> Stuff related to csv columns
    def self.columns
      @columns = []
    end

    def self.csv_columns(*list)
      @columns = list
    end
    ## <-
    ############

    ############
    ## -> Stuff related to persistent maps (of ID-s?)
    def data_dir
      'data'
    end

    def self.maps
      @maps
    end

    def self.persistent_maps(*list)
      @maps = list
    end

    def load_maps
      @pm = {}
      @cache = {}
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

    def save_maps
      self.class.maps.each do |map_sym|
        next if @pm[map_sym].new.empty?
        CSV.open((File.join data_dir, "#{map_sym}-#{Time.now.utc.iso8601}.csv"), "wb", {:force_quotes => true}) do |csv|
          csv << ['sat5', 'sat6']
          @pm[map_sym].new.each do |key,value|
            csv << [key, value]
          end
        end
      end
    end
    ## <-
    ############

    def import_init
    end

    def import_single_row(row)
    end

    def lookup_entity(entity_type, entity_id)
      puts "lookup: #{entity_type}: #{entity_id}"
      return @api.resource(entity_type).call(:show, {"id" => entity_id})
    end

    def create_entity(entity_type, entity_hash, original_id)
      type = entity_type.to_s.sub(/s$/, "")
      if @pm[entity_type][original_id.to_i]
        puts type + " " + original_id + " already imported."
        return @cache[entity_type][@pm[entity_type][original_id.to_i]]
      else
        puts "Creating new " + type + ": " + entity_hash.values_at(:name, :label, :login).compact[0]
        entity_hash = {@wrap_out[entity_type] => entity_hash} if @wrap_out[entity_type]
        entity = @api.resource(entity_type).call(:create, entity_hash)
        p "created entity:", entity
        entity = entity[@wrap_in[entity_type]] if @wrap_in[entity_type]
        @pm[entity_type][original_id.to_i] = entity["id"]
        @cache[entity_type][entity["id"]] = entity
        p "@pm[entity_type]:", @pm[entity_type]
        return entity
      end
    end

    def import(filename)
      reader = CSV.open(filename, 'r')
      header = reader.shift
      self.class.columns.each do |col|
        raise CSVHeaderError, "column #{col} expected in #{filename}" unless header.include? col
      end

      reader.each do |row|
        import_single_row(Hash[header.zip row])
      end
    end

    def execute
      @wrap_out = {:users => :user}
      @wrap_in = {:organizations => "organization"}

      @api = ApipieBindings::API.new({
        :uri => HammerCLI::Settings.get(:foreman, :host),
        :username => HammerCLI::Settings.get(:foreman, :username),
        :password => HammerCLI::Settings.get(:foreman, :password),
        :api_version => 2
      })

      load_maps
      import_init
      import option_csv_file
      save_maps
      HammerCLI::EX_OK
    end
  end
end

