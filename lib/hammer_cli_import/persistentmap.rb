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
require 'set'

module PersistentMap
  class PersistentMapError < RuntimeError
  end

  class << Fixnum
    def from_s(x)
      Integer(x) rescue 0
    end
  end

  class << String
    def from_s(x)
      x
    end
  end

  class << self
    def definitions
      return @definitions if @definitions
      @definitions = {}

      [:content_views, :host_collections, :organizations, :repositories, :users].each do |symbol|
        @definitions[symbol] = ['sat5' => Fixnum], ['sat6' => Fixnum], symbol
      end

      @definitions[:activation_keys] = ['org_id' => String], ['sat6' => Fixnum], :activation_keys
      @definitions[:ak_content_views] = ['ak_id' => String], ['sat6' => Fixnum], :content_views
      @definitions[:system_content_views] = ['ch_seq' => String], ['sat6' => Fixnum], :content_views
      @definitions[:local_repositories] = [{'org_id' => Fixnum}, {'channel_id' => Fixnum}], ['sat6' => Fixnum], :repositories
      @definitions[:products] = [{'org_id' => Fixnum}, {'label' => String}], ['sat6' => Fixnum], :products
      @definitions[:puppet_repositories] = [{'org_id' => Fixnum}, {'channel_id' => Fixnum}],
                                           ['sat6' => Fixnum], :repositories
      @definitions[:redhat_content_views] = [{'org_id' => Fixnum}, {'channel_id' => Fixnum}], ['sat6' => Fixnum],
                                            :content_views
      @definitions[:redhat_repositories] = [{'org_id' => Fixnum}, {'channel_id' => Fixnum}], ['sat6' => Fixnum],
                                           :repositories
      @definitions[:hosts] = ['sat5' => Fixnum], ['sat6' => String], :hosts
      @definitions[:template_snippets] = ['id' => Fixnum], ['sat6' => Fixnum], :config_templates

      @definitions.freeze
    end
  end

  module Extend
    attr_reader :maps, :map_description, :map_target_entity

    def persistent_map(symbol)
      defs = PersistentMap.definitions

      raise PersistentMapError, "Unknown persistent map: #{symbol}" unless defs.key? symbol

      # Names of persistent maps
      @maps ||= []
      @maps.push symbol

      key_spec, val_spec, target_entity = defs[symbol]

      # Which entities they are mapped to?
      # Usually they are mapped to the same entities on Sat6 (speaking of api)
      # But sometimes you need to create same type of Sat6 entities based on
      # different Sat5 entities, and then it is time for this extra option.
      @map_target_entity ||= {}
      @map_target_entity[symbol] = target_entity

      # How keys and values looks like (so they can be nicely stored)
      @map_description ||= {}
      @map_description[symbol] = [key_spec, val_spec]
    end

    def persistent_maps(*list)
      raise PersistentMapError, 'Persistent maps should be declared only once' if @maps
      list.each do |map_sym|
        persistent_map map_sym
      end
    end
  end

  module Include
    def maps
      self.class.maps
    end

    def map_target_entity
      self.class.map_target_entity
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
        @pm[map_sym] = add_checks(DeltaHash[hash], self.class.map_description[map_sym], map_sym)
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

    # Consider entities deleted if they are not present in cache
    def prune_persistent_maps(cache)
      maps.each do |map_sym|
        entity_ids = cache[map_target_entity[map_sym]].keys
        pm_hash = @pm[map_sym].to_hash
        extra = pm_hash.values.to_set - entity_ids.to_set

        next if extra.empty?

        debug "Removing #{map_sym} from persistent map: #{extra.to_a.join(' ')}"
        pm_hash.each do |key, value|
          @pm[map_sym].delete key if extra.include? value
        end
      end
    end

    private

    # Protective black magic.
    # Checks whether given values and keys matches description
    # at the moment of insertion...
    def add_checks(hash, kv_desc, map_sym)
      hash.instance_eval do
        ks, vs = kv_desc
        @key_desc = ks.collect(&:values) .flatten
        @val_desc = vs.collect(&:values) .flatten
        @map_sym = map_sym
      end
      class << hash
        def []=(ks, vs)
          key = ks
          val = vs
          key = [key] unless key.is_a? Array
          val = [val] unless val.is_a? Array
          raise "Bad key for persistent map #{@map_sym}: (#{key.inspect} - #{@key_desc.inspect})" \
            unless key.size == @key_desc.size && key.zip(@key_desc).all? { |k, d| k.is_a? d }
          raise "Bad value for persistent map #{@map_sym}: (#{val.inspect} - #{@val_desc.inspect}" \
            unless val.size == @val_desc.size && val.zip(@val_desc).all? { |v, d| v.is_a? d }
          super
        end
      end
      hash
    end

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
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
