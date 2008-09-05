module DataFabric
  # This module is included into ActiveRecord model classes that are replicated
  # (i.e. models that have 'data_fabric ..., :replicated => true' specified).
  #
  # It overrides some of ActiveRecord::Base's behavior in order to make it
  # work with master-slave database replication.
  module ReplicationExtensions
    def self.included(base)
      base.alias_method_chain :reload, :master
    end
    
    def reload_with_master(*args, &block)
      # We want ActiveRecord::Base#reload to go through the master.
      connection.with_master { reload_without_master }
    end
  end
end
