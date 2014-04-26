require 'set'

class DeltaHashError < RuntimeError
end

class DeltaHash
  attr_reader :new
  attr_reader :del

  def self.[](hash)
    new(hash)
  end

  def initialize(hash)
    @old = hash
    @new = {}
    @del = Set.new
  end

  def [](key)
    return nil if @del.include? key
    @new[key] || @old[key]
  end

  def []=(key, val)
    fail DeltaHashError, 'Key exists' if self[key]
    @del.delete key
    @new[key] = val unless @old[key] == val
  end

  def to_hash
    ret = (@old.merge @new)
    @del.each do |key|
      ret.delete key
    end
    ret
  end

  def delete(key)
    fail DeltaHashError, 'Key does not exist' unless self[key]
    @del << key if @old[key]
    @new.delete(key)
  end

  def to_s
    to_hash.to_s
  end

  def inspect
    to_hash.inspect
  end
end
