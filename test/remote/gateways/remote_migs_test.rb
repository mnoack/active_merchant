require 'test_helper'

class RemoteMigsTest < Test::Unit::TestCase
  

  def setup
    @gateway = MigsGateway.new(fixtures(:migs))
    
    @amount = 100
    @declined_amount = 105
    @credit_card = credit_card('4005550000000001', :month => 5, :year => 2013)
    
    @options = { 
      :order_id => '1',
    }
  end
  
  def test_successful_purchase
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Approved', response.message
  end

  def test_unsuccessful_purchase
    assert response = @gateway.purchase(@declined_amount, @credit_card, @options)
    assert_failure response
    assert_equal 'Declined', response.message
  end

  def test_authorize_and_capture
    @options[:advanced_login] = 'testuser'
    @options[:advanced_password] = 'testpass'
    amount = @amount
    assert auth = @gateway.authorize(amount, @credit_card, @options)
    assert_success auth
    assert_equal 'Approved', auth.message
    assert auth.authorization
    assert capture = @gateway.capture(amount, auth.authorization, @options)
    assert_success capture
  end

  def test_failed_capture
    assert response = @gateway.capture(@declined_amount, @credit_card, @options)
    assert_failure response
    assert_equal 'Declined', response.message
  end

  def test_invalid_login
    gateway = MigsGateway.new(
                :login => '',
                :password => ''
              )
    assert response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'Required field vpc_Merchant was not present in the request', response.message
  end
end
