# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'csv'

module CSVHelper
  class CSVHelperError < RuntimeError
  end

  def self.csv_each(filename, headers)
    fail CSVHelperError, 'Expecting block' unless block_given?
    reader = CSV.open(filename, 'r')
    real_header = reader.shift
    to_discard = real_header - headers
    headers.each do |col|
      raise CSVHelperError, "column #{col} expected in #{filename}" unless real_header.include? col
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
end
