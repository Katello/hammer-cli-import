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

    ############
    ## -> Stuff related to csv columns
    def self.columns
      @columns
    end

    def self.csv_columns(*list)
      @columns = list
    end
    ## <-
    ############

    ############
    ## -> Stuff related to persistent maps (of ID-s?)
    def self.maps
      @maps
    end

    def self.persistent_maps(*list)
      @maps = list
    end

    def load_maps()
      self.class.maps.each do |map_sym|
        hash = {}
        Dir["data/#{map_sym}-*.csv"].sort.each do |filename|
          reader = CSV.open(filename, 'r')
          header = reader.shift
          raise PersistentMapError, "Importing :#{map_sym} from file #{filename}" unless header == ['sat5', 'sat6']
          reader.each do |row|
            hash[row[0].to_i] = row[1].to_i
          end
        end
        instance_variable_set "@pm_#{map_sym}", RememberHash.new(hash)
      end
    end

    def save_maps()
      self.class.maps.each do |map_sym|
        hash = instance_variable_get "@pm_#{map_sym}"
        CSV.open("data/#{map_sym}-#{Time.now.utc.iso8601}.csv", "wb", {:force_quotes => true}) do |csv|
          csv << ['sat5', 'sat6']
          hash.each do |key,value|
            csv << [key, value]
          end
        end
      end
    end
    ## <-
    ############

    def import_init()
    end

    def import_single_row(row)
    end

    def import(filename)
      reader = CSV.open(filename, 'r')
      header = reader.shift
      self.class.columns.each do |col|
        raise CSVHeaderError, "columnt #{col} expected in #{filename}" unless header.include? col
      end

      reader.each do |row|
        import_single_row(Hash[header.zip row])
      end
    end

    def execute
      @api = ApipieBindings::API.new({
        :uri => HammerCLI::Settings.get(:foreman, :host),
        :username => HammerCLI::Settings.get(:foreman, :username),
        :password => HammerCLI::Settings.get(:foreman, :password),
        :api_version => 2
      })

      load_maps()
      import_init
      import (option_csv_file)
      save_maps()
      HammerCLI::EX_OK
    end
  end
end

