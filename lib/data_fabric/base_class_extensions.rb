module DataFabric
  # Class methods injected into ActiveRecord::Base.
  module BaseClassExtensions
    # Indicate that this ActiveRecord model is either sharded or uses
    # master-slave replication, or both.
    #
    # Allowed options:
    # - +:shard_by+: The shard group that this model lives in.
    # - +:replicated+: a Boolean which indicates whether master-slave
    #   replication is used. Default: false.
    # - +:prefix+
    #
    #   class SomeModel < ActiveRecord::Base
    #     data_fabric :replicated
    #   end
    def data_fabric(options)
      proxy = DataFabric::ConnectionProxy.new(self, options)
      ActiveRecord::Base.active_connections[name] = proxy
      
      raise ArgumentError, "data_fabric does not support ActiveRecord's allow_concurrency = true" if allow_concurrency
      DataFabric.logger.info("Creating data_fabric proxy for class #{name}")
    end
    
    alias :connection_topology :data_fabric # legacy
  end
end
