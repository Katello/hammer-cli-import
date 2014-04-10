module HammerCLIImport
  class RememberHash < Hash
    attr_reader :old

    def initialize(a, *list)
      super(*list)
      @old = a
    end

    def []=(key,val)
      @old[key] = val
      super(key, val)
    end
    def [](key)
      super(key) || @old[key]
    end
  end
end
