require File.join(File.dirname(__FILE__), 'test_helper')
require 'flexmock/test_unit'
require 'erb'

class TheWholeBurrito < ActiveRecord::Base
  connection_topology :prefix => 'fiveruns', :replicated => true, :shard_by => :city
end

class DatabaseTest < Test::Unit::TestCase
  
  def setup
    ActiveRecord::Base.configurations = load_database_yml
  end
  
  def teardown
    DataFabric.clear_connection_pool!
  end

  def test_live_burrito
    DataFabric.activate_shard :city => :dallas do
      assert_equal 'fiveruns_city_dallas_test_slave', TheWholeBurrito.connection.connection_name

      # Should use the slave
      burrito = TheWholeBurrito.find(1)
      assert_equal 'vr_dallas_slave', burrito.name
      
      # Should use the master
      burrito.reload
      assert_equal 'vr_dallas_master', burrito.name

      # ...but immediately set it back to default to the slave
      assert_equal 'fiveruns_city_dallas_test_slave', TheWholeBurrito.connection.connection_name
      
      # Should use the master
      TheWholeBurrito.transaction do
        burrito = TheWholeBurrito.find(1)
        assert_equal 'vr_dallas_master', burrito.name
        burrito.save!
      end
    end
  end
end
