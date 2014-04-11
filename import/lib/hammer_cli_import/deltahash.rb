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
    unless self[key] == val
      @new[key] = val
    end
  end

  def to_h
    @old.merge @new
  end

  def new
    @new
  end
end
