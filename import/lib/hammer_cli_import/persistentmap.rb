require 'csv'

module PersistentMap
  class PersistentMapError < RuntimeError
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

  module Extend
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

  module Include
    def maps
      self.class.maps
    end

    def load_persistent_maps
      @pm = {}
      maps.each do |map_sym|
        hash = {}
        Dir[File.join data_dir, "#{map_sym}-*.csv"].sort.each do |filename|
          reader = CSV.open(filename, 'r')
          header = reader.shift
          raise PersistentMapError, "Importing :#{map_sym} from file #{filename}" unless header == (pm_csv_headers map_sym)
          reader.each do |row|
            key, value = pm_decode_row map_sym, row
            delkey = row[-1] == '-'
            if delkey
              hash.delete key
            else
              hash[key] = value
            end
          end
        end
        @pm[map_sym] = DeltaHash[hash]
        yield map_sym if block_given?
      end
    end

    def save_persistent_maps
      maps.each do |map_sym|
        next unless @pm[map_sym].changed?
        CSV.open((File.join data_dir, "#{map_sym}-#{Time.now.utc.iso8601}.csv"), 'wb') do |csv|
          csv << (pm_csv_headers map_sym)
          @pm[map_sym].new.each do |key, value|
            key = [key] unless key.is_a? Array
            value = [value] unless value.is_a? Array
            csv << key + value + [nil]
          end
          delval = [nil] * (val_arity map_sym)
          @pm[map_sym].del.each do |key|
            key = [key] unless key.is_a? Array
            csv << key + delval + ['-']
          end
        end
      end
    end

    private

    def pm_decode_row(map_sym, row)
      key_spec, val_spec = self.class.map_description[map_sym]
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

    def pm_csv_headers(symbol)
      key_spec, val_spec = self.class.map_description[symbol]
      (key_spec + val_spec).collect { |x| x.keys[0] } + ['delete']
    end

    def val_arity(symbol)
      _key_spec, val_spec = self.class.map_description[symbol]
      val_spec.size
    end
  end
end
