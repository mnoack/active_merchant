require 'test_helper'
require 'net/http'

class RemoteMigsTest < Test::Unit::TestCase
  

  def setup
    @gateway = MigsGateway.new(fixtures(:migs))
    
    @amount = 100
    @declined_amount = 105
    @credit_card = credit_card('4005550000000001', :month => 5, :year => 2013)
    @visa   = @credit_card
    @master = credit_card('5123456789012346', :month => 5, :year => 2013, :type => 'master')
    @amex   = credit_card('345678901234564', :month => 5, :year => 2013, :type => 'american_express')
    @diners = credit_card('30123456789019', :month => 5, :year => 2013, :type => 'diners_club')
    
    @options = { 
      :order_id => '1'
    }
  end

  def test_server_purchase_url
    options = {
      order_id: 1,
      unique_id: 9,
      return_url: 'http://localhost:8080/payments/return'
    }

    choice_url = @gateway.purchase_offsite_url(@amount, nil, options)
    assert_response_contains 'Pay securely by clicking on the card logo below', choice_url

    visa_url = @gateway.purchase_offsite_url(@amount, @visa, options)
    assert_response_contains 'You have chosen <B>VISA</B>', visa_url

    master_url = @gateway.purchase_offsite_url(@amount, @master, options)
    assert_response_contains 'You have chosen <B>MasterCard</B>', master_url

    diners_url = @gateway.purchase_offsite_url(@amount, @diners, options)
    assert_response_contains 'You have chosen <B>Diners Club</B>', diners_url

    amex_url = @gateway.purchase_offsite_url(@amount, @amex, options)
    assert_response_contains 'You have chosen <B>American Express</B>', amex_url
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

  # Cannot test as test gateway does not allow auth/capture mode
  #def test_authorize_and_capture
  #  assert auth = @gateway.authorize(@amount, @credit_card, @options)
  #  assert_success auth
  #  assert_equal 'Approved', auth.message
  #  assert capture = @gateway.capture(@amount, auth.params['TransactionNo'], @options)
  #  assert_success capture
  #end
  #
  #def test_failed_capture
  #  assert response = @gateway.capture(@declined_amount, @credit_card, @options)
  #  assert_failure response
  #  assert_equal 'Declined', response.message
  #end

  def test_refund
    assert payment_response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success payment_response
    assert response = @gateway.refund(@amount, payment_response.params['TransactionNo'], @options)
    assert_success response
    assert_equal 'Approved', response.message
  end

  def test_status
    purchase_response = @gateway.purchase(@declined_amount, @credit_card, @options)
    assert response = @gateway.status(purchase_response.params['MerchTxnRef'])
    assert_equal 'Y', response.params['DRExists']
    assert_equal 'N', response.params['FoundMultipleDRs']
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

  private

  def assert_response_contains(text, url)
    response = https_response(url)
    assert response.body.include?(text)
  end

  def https_response(url, cookie = nil)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(uri.request_uri)
    request['Cookie'] = cookie if cookie
    response = http.request(request)
    if response.is_a?(Net::HTTPRedirection)
      new_cookie = [cookie, response['Set-Cookie']].compact.join(';')
      response = https_response(response['Location'], new_cookie)
    end
    response
  end

end
