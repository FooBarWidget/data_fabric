require File.join(File.dirname(__FILE__), 'test_helper')

class BasicTest < Test::Unit::TestCase
  def test_data_fabric_method_is_installed_into_active_record_base
    assert ActiveRecord::Base.methods.include?('data_fabric')
  end
end
