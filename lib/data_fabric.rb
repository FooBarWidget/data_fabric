require 'active_record'
require 'active_record/version'

require 'data_fabric/base_class_extensions'
require 'data_fabric/string_proxy'
require 'data_fabric/connection_proxy'
require 'data_fabric/replication_extensions'
require 'data_fabric/version'

# DataFabric adds a new level of flexibility to ActiveRecord connection handling.
# You need to describe the topology for your database infrastructure in your model(s).  As with ActiveRecord normally, different models can use different topologies.
# 
# class MyHugeVolumeOfDataModel < ActiveRecord::Base
#   data_fabric :replicated => true, :shard_by => :city
# end
# 
# There are four supported modes of operation, depending on the options given to the data_fabric method.  The plugin will look for connections in your config/database.yml with the following convention:
# 
# No connection topology:
# #{environment} - this is the default, as with ActiveRecord, e.g. "production"
# 
# data_fabric :replicated => true
# #{environment}_#{role} - no sharding, just replication, where role is "master" or "slave", e.g. "production_master"
# 
# data_fabric :shard_by => :city
# #{group}_#{shard}_#{environment} - sharding, no replication, e.g. "city_austin_production"
# 
# data_fabric :replicated => true, :shard_by => :city
# #{group}_#{shard}_#{environment}_#{role} - sharding with replication, e.g. "city_austin_production_master"
# 
# 
# When marked as replicated, all write and transactional operations for the model go to the master, whereas read operations go to the slave.
# 
# Since sharding is an application-level concern, your application must set the shard to use based on the current request or environment.  The current shard for a group is set on a thread local variable.  For example, you can set the shard in an ActionController around_filter based on the user as follows:
# 
# class ApplicationController < ActionController::Base
#   around_filter :select_shard
#   
#   private
#   def select_shard(&action_block)
#     DataFabric.activate_shard(:city => @current_user.city, &action_block)
#   end
# end
module DataFabric
  
  def self.logger
    ActiveRecord::Base.logger
  end

  def self.init
    logger.info "Loading data_fabric #{DataFabric::Version::STRING} with ActiveRecord #{ActiveRecord::VERSION::STRING}"
    ActiveRecord::Base.send(:include, self)
  end
  
  mattr_writer :debugging
  @@debugging = false
  
  def self.debugging?
    if @@debugging.nil? && logger
      logger.debug?
    else
      !!@@debugging
    end
  end
  
  def self.clear_connection_pool!
    (Thread.current[:data_fabric_connections] ||= {}).clear
  end
  
  def self.activate_shard(shards, &block)
    if debugging?
      logger.debug("Activating shard: #{shards.inspect}")
    end
    ensure_setup

    if block_given?
      # Save the old shard settings to handle nested activation
      old = Thread.current[:shards].dup
    end

    shards.each_pair do |key, value|
      Thread.current[:shards][key.to_s] = value.to_s
    end
    if block_given?
      begin
        yield
      ensure
        if debugging?
          logger.debug("Auto-deactivating shard: #{shards.inspect}")
        end
        Thread.current[:shards] = old
      end
    end
  end
  
  # For cases where you can't pass a block to activate_shards, you can
  # clean up the thread local settings by calling this method at the
  # end of processing
  def self.deactivate_shard(shards)
    if debugging?
      logger.debug("Manually deactivating shard: #{shards.inspect}")
    end
    ensure_setup
    shards.each do |key, value|
      Thread.current[:shards].delete(key.to_s)
    end
  end
  
  def self.active_shard(group)
    raise ArgumentError, 'No shard has been activated' unless Thread.current[:shards]

    returning(Thread.current[:shards][group.to_s]) do |shard|
      raise ArgumentError, "No active shard for #{group}" unless shard
    end
  end
  
  def self.included(model)
    # Wire up ActiveRecord::Base
    model.extend BaseClassExtensions
  end

  def self.ensure_setup
    Thread.current[:shards] = {} unless Thread.current[:shards]
  end
end
