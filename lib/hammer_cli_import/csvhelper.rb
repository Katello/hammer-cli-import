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

module CSVHelper
  class CSVHelperError < RuntimeError
  end

  # Returns missing columns
  def self.csv_missing_columns(filename, headers)
    reader = CSV.open(filename, 'r')
    real_header = reader.shift
    reader.close
    headers - real_header
  end

  def self.csv_each(filename, headers)
    raise CSVHelperError, 'Expecting block' unless block_given?
    reader = CSV.open(filename, 'r')
    real_header = reader.shift
    raise CSVHelperError, "No header in #{filename}" if real_header.nil?
    to_discard = real_header - headers
    headers.each do |col|
      raise CSVHelperError, "Column #{col} expected in #{filename}" unless real_header.include? col
    end
    reader.each do |row|
      data = Hash[real_header.zip row]
      to_discard.each { |key| data.delete key }
      class << data
        def[](key)
          raise CSVHelperError, "Referencing undeclared key: #{key}" unless key? key
          super
        end
      end
      yield data
    end
  end

  def self.csv_write_hashes(filename, headers, hashes)
    CSV.open(filename, 'wb') do |csv|
      csv << headers
      hashes.each do |hash|
        csv << headers.collect { |key| hash[key] }
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
