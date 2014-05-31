# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'csv'

module CSVHelper
  class CSVHelperError < RuntimeError
  end

  def self.csv_each(filename, headers)
    fail CSVHelperError, 'Expecting block' unless block_given?
    reader = CSV.open(filename, 'r')
    real_header = reader.shift
    fail CSVHelperError, "No header in #{filename}" if real_header.nil?
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
