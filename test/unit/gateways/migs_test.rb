require 'test_helper'

class MigsTest < Test::Unit::TestCase
  def setup
    @gateway = MigsGateway.new(
                 :login => 'login',
                 :password => 'password'
               )

    @credit_card = credit_card
    @amount = 100
    
    @options = { 
      :order_id => '1',
      :billing_address => address,
      :description => 'Store Purchase'
    }
  end
  
  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_success response
    
    # Replace with authorization number from the successful response
    assert_equal '123456', response.authorization
  end

  def test_unsuccessful_request
    @gateway.expects(:ssl_post).returns(failed_purchase_response)
    
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_failure response
    
    assert_equal '654321', response.authorization
  end

  private
  
  # Place raw successful response from gateway here
  def successful_purchase_response
    build_response(
      :TxnResponseCode => '0',
      :TransactionNo => '123456'
    )
  end
  
  # Place raw failed response from gateway here
  def failed_purchase_response
    build_response(
      :TxnResponseCode => '3',
      :TransactionNo => '654321'
    )
  end
  
  def build_response(options)
    options.collect { |key, value| "vpc_#{key}=#{CGI.escape(value.to_s)}"}.join('&')
  end
end
