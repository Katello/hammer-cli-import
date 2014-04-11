class DeltaHashError < RuntimeError
end

class DeltaHash
  attr_reader :new

  def self.[](hash)
    new(hash)
  end

  def initialize(hash)
    @old = hash
    @new = {}
  end

  def [](key)
    @new[key] || @old[key]
  end

  def []=(key, val)
    fail DeltaHashError, 'Key exists' if self[key]
    @new[key] = val
  end

  def to_h
    @old.merge @new
  end
end
