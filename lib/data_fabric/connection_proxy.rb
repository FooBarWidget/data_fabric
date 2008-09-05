module DataFabric
  # This class emulates ActiveRecord::ConnectionAdapters::AbstractAdapter, but
  # adds master-slave replication and sharding logic. For models that use
  # DataFabric, 'SomeModel.connection' will return an instance of this class.
  #
  # Internally, ConnectionProxy maintains a number of
  # ActiveRecord::ConnectionAdapters::AbstractAdapter objects, and forwards
  # SQL queries to one of those objects, based on the sharding/replication
  # rules.
  class ConnectionProxy
    def initialize(model_class, options)
      @model_class = model_class      
      @replicated = options[:replicated]
      @shard_group = options[:shard_by]
      @prefix = options[:prefix]
      @current_role = 'slave' if @replicated
      @current_connection_name_builder = connection_name_builder
      @cached_connection = nil
      @current_connection_name = nil
      @role_changed = false

      @model_class.send :include, ReplicationExtensions if @replicated
    end
    
    def self.delegate_directly(*methods)
      methods.each do |method|
        eval "
          def #{method}(*args)
            connection_adapter = @adapter_mock || ActiveRecord::Base.connection
            connection_adapter.#{method}(*args)
          end
        "
      end
    end
    
    class << self
      private :delegate_directly
    end

    delegate :insert, :update, :delete, :create_table, :rename_table, :drop_table, :add_column, :remove_column, 
      :change_column, :change_column_default, :rename_column, :add_index, :remove_index, :initialize_schema_information,
      :dump_schema_information, :execute, :to => :master
    
    delegate_directly :requires_reloading?, :columns, :indexes, :quote, :quote_table_name,
      :quote_column_name, :quoted_table_name, :add_limit, :add_limit_offset!, :add_lock!,
      :table_exists?
    
    attr_accessor :adapter_mock
    
    def transaction(start_db_transaction = true, &block)
      with_master { raw_connection.transaction(start_db_transaction, &block) }
    end

    def method_missing(method, *args, &block)
      unless @cached_connection and !@role_changed
        raw_connection
        @role_changed = false
      end
      if DataFabric.debugging?
        logger.debug("Calling #{method} on #{@cached_connection}")
      end
      raw_connection.send(method, *args, &block)
    end
    
    def connection_name
      @current_connection_name_builder.join('_')
    end
    
    def disconnect!
      @cached_connection.disconnect! if @cached_connection
      @cached_connection = nil
    end
    
    def verify!(arg)
      @cached_connection.verify!(0) if @cached_connection
    end
    
    def with_master
      set_role('master')
      yield
    ensure
      set_role('slave')
    end
    
    def raw_connection
      conn_name = connection_name
      unless already_connected_to? conn_name 
        @cached_connection = begin 
          connection_pool = (Thread.current[:data_fabric_connections] ||= {})
          conn = connection_pool[conn_name]
          if !conn
            if DataFabric.debugging?
              logger.debug "Switching from #{@current_connection_name || "(none)"} to #{conn_name} (new connection)"
            end
            config = ActiveRecord::Base.configurations[conn_name]
            raise ArgumentError, "Unknown database config: #{conn_name}, have #{ActiveRecord::Base.configurations.inspect}" unless config
            @model_class.establish_connection config
            conn = @model_class.connection
            connection_pool[conn_name] = conn
          elsif DataFabric.debugging?
            logger.debug "Switching from #{@current_connection_name || "(none)"} to #{conn_name} (existing connection)"
          end
          @current_connection_name = conn_name
          conn.verify!(-1)
          conn
        end
        @model_class.active_connections[@model_class.name] = self
      end
      @cached_connection
    end

    private
    
    def connection_name_builder
      clauses = []
      clauses << @prefix if @prefix
      clauses << @shard_group if @shard_group
      clauses << StringProxy.new { DataFabric.active_shard(@shard_group) } if @shard_group
      clauses << RAILS_ENV
      clauses << StringProxy.new { @current_role } if @replicated
      clauses
    end
    
    def already_connected_to?(conn_name)
      conn_name == @current_connection_name and @cached_connection
    end
    
    def set_role(role)
      if @replicated and @current_role != role
        @current_role = role
        @role_changed = true
      end
    end
    
    def master
      set_role('master')
      return raw_connection
    ensure
      set_role('slave')
    end
    
    def logger
      DataFabric.logger
    end
  end
end
