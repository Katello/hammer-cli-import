class DeltaHashError < RuntimeError
end

class DeltaHash
  def self.[](hash)
    self.new(hash)
  end

  def initialize(hash)
    @old = hash
    @new = {}
  end

  def [](key)
    @new[key] || @old[key]
  end

  def []=(key, val)
    fail DeltaHashError, "Key exists" if self[key]
    @new[key] = val
  end

  def to_h
    @old.merge @new
  end

  def new
    @new
  end
end
