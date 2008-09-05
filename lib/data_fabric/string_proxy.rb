module DataFabric
  # A class whose #to_s return value equals the block that's passed to
  # the constructor.
  #
  #   i = 0
  #   s = DataFabric::StringProxy.new do
  #     i += 1
  #     i.to_s
  #   end
  #   
  #   s.to_s  # => 1
  #   s.to_s  # => 2
  class StringProxy
    def initialize(&block)
      @proc = block
    end
    
    def to_s
      @proc.call
    end
  end
end
