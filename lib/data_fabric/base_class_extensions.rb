module DataFabric
  # Class methods injected into ActiveRecord::Base.
  module BaseClassExtensions
    def data_fabric(options)
      proxy = DataFabric::ConnectionProxy.new(self, options)
      ActiveRecord::Base.active_connections[name] = proxy
      
      raise ArgumentError, "data_fabric does not support ActiveRecord's allow_concurrency = true" if allow_concurrency
      DataFabric.logger.info("Creating data_fabric proxy for class #{name}")
    end
    
    alias :connection_topology :data_fabric # legacy
  end
end
