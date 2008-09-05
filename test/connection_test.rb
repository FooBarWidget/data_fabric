require File.join(File.dirname(__FILE__), 'test_helper')
require 'flexmock/test_unit'

class PrefixModel < ActiveRecord::Base
  data_fabric :prefix => 'prefix'
end

class ShardModel < ActiveRecord::Base
  data_fabric :shard_by => :city
end

class TheWholeEnchilada < ActiveRecord::Base
  data_fabric :prefix => 'fiveruns', :replicated => true, :shard_by => :city
end

# A mock class which emulates AbstractAdapter. Contains the minimum code
# required to perform a find with no results.
class AdapterMock < ActiveRecord::ConnectionAdapters::AbstractAdapter
   def columns(table_name, name = nil)
     []
   end
   
   def select(sql, name = nil)
     []
   end
   
   def execute(sql, name = nil)
     0
   end
   
   def name
     'fake-db'
   end
  
   def method_missing(name, *args)
     raise ArgumentError, "#{self.class.name} missing '#{name}': #{args.inspect}"
   end
end

# The raw database driver object for AdapterMock.
class RawConnection
  def method_missing(name, *args)
    puts "#{self.class.name} missing '#{name}': #{args.inspect}"
  end
end

class ConnectionTest < Test::Unit::TestCase
  def teardown
    DataFabric.clear_connection_pool!
  end

  def test_prefix_is_added_to_the_connection_name
    setup_configuration_for PrefixModel, 'prefix_test'
    assert_equal 'prefix_test', PrefixModel.connection.connection_name
  end
  
  def test_shard_is_added_to_the_connection_name
    setup_configuration_for ShardModel, 'city_austin_test'
    # ensure unset means error
    assert_raises ArgumentError do
      ShardModel.connection.connection_name
    end
    DataFabric.activate_shard(:city => 'austin', :category => 'art') do
      assert_equal 'city_austin_test', ShardModel.connection.connection_name
    end
    # ensure it got unset
    assert_raises ArgumentError do
      ShardModel.connection.connection_name
    end
  end
  
  def test_enchilada
    setup_configuration_for TheWholeEnchilada, 'fiveruns_city_dallas_test_slave'
    setup_configuration_for TheWholeEnchilada, 'fiveruns_city_dallas_test_master'
    DataFabric.activate_shard :city => :dallas do
      assert_equal 'fiveruns_city_dallas_test_slave', TheWholeEnchilada.connection.connection_name

      # Should use the slave
      assert_raises ActiveRecord::RecordNotFound do
        TheWholeEnchilada.find(1)
      end
      
      # Should use the master
      mmmm = TheWholeEnchilada.new
      mmmm.instance_variable_set(:@attributes, { 'id' => 1 })
      assert_raises ActiveRecord::RecordNotFound do
        mmmm.reload
      end
      # ...but immediately set it back to default to the slave
      assert_equal 'fiveruns_city_dallas_test_slave', TheWholeEnchilada.connection.connection_name
      
      # Should use the master
      TheWholeEnchilada.transaction do
        mmmm.save!
      end
    end
  end
  
  def test_activating_a_shard_will_only_reconnect_to_database_if_necessary
    setup_configuration_for TheWholeEnchilada, 'fiveruns_city_dallas_test_slave'
    setup_configuration_for TheWholeEnchilada, 'fiveruns_city_dallas_test_master'
    DataFabric.activate_shard :city => :dallas do
      old_connection = TheWholeEnchilada.connection.raw_connection
      DataFabric.activate_shard :city => :austin do
        DataFabric.activate_shard :city => :dallas do
          new_connection = TheWholeEnchilada.connection.raw_connection
          assert_equal old_connection, new_connection
        end
      end
    end
  end

  private
  
  # Makes sure that when the database shard with the name +name+ is activated,
  # that a fake database connection for the model class 'clazz' is activated.
  # This is done by making sure that Model.connection.raw_connection returns an
  # AdapterMock object instead of a real database driver object.
  #
  # Precondition: +data_fabric+ must have been called within +clazz+.
  def setup_configuration_for(clazz, name)
    ActiveRecord::Base.configurations ||= HashWithIndifferentAccess.new
    ActiveRecord::Base.configurations[name] = HashWithIndifferentAccess.new({
      :adapter => 'mysql',
      :database => name,
      :host => 'localhost'
    })
    clazz.connection.adapter_mock = AdapterMock.new(RawConnection.new)
    flexmock(clazz).should_receive(:mysql_connection).and_return(clazz.connection.adapter_mock)
  end
end
