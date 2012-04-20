require File.dirname(__FILE__) + '/migs/migs_codes'

require 'digest/md5' # Used in add_secure_hash

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class MigsGateway < Gateway
      include MigsCodes

      API_VERSION = 1

      SERVER_HOSTED_URL = 'https://migs.mastercard.com.au/vpcpay'
      MERCHANT_HOSTED_URL = 'https://migs.mastercard.com.au/vpcdps'

      
      # The countries the gateway supports merchants from as 2 digit ISO country codes
      # MiGS is supported throughout Asia Pacific, Middle East and Africa
      # MiGS is used in Australia (AU) by ANZ, CBA, Bendigo and more
      # Source of Country List: http://www.scribd.com/doc/17811923
      self.supported_countries = %w(AU AE BD BN EG HK ID IN JO KW LB LK MU MV MY NZ OM PH QA SA SG TT VN)
      
      # The card types supported by the payment gateway
      self.supported_cardtypes = [:visa, :master, :american_express, :diners_club, :jcb]
      
      self.money_format = :cents
      
      # The homepage URL of the gateway
      self.homepage_url = 'http://mastercard.com/mastercardsps'
      
      # The name of the gateway
      self.display_name = 'MasterCard Internet Gateway Service (MiGS)'

      def initialize(options = {})
        requires!(options, :login, :password)
        @test = options[:login].start_with?('TEST')
        @options = options
        super
      end

      def purchase(money, creditcard, options = {})
        requires!(options, :order_id)

        post = {}
        post[:Amount] = amount(money)
        add_invoice(post, options)
        add_creditcard(post, creditcard)
        add_address(post, creditcard, options)
        add_customer_data(post, options)
        add_standard_parameters('pay', post)

        commit(post)
      end

      # MiGS works by merchants being either purchase only or authorize + captures
      # Where to authorize you do the same as a purchase
      alias_method :authorize, :purchase

      def capture(money, authorization, options = {})
        requires!(@options, :advanced_login, :advanced_password)

        post = options.merge(:TransNo => authorization)
        post[:Amount] = amount(money)
        add_advanced_user(post)
        add_standard_parameters('capture', post)

        commit(post)
      end

      def refund(money, authorization, options = {})
        requires!(@options, :advanced_login, :advanced_password)

        post = options.merge(:TransNo => authorization)
        post[:Amount] = amount(money)
        add_advanced_user(post)
        add_standard_parameters('refund', post)

        commit(post)
      end

      def credit(money, authorization, options = {})
        deprecated CREDIT_DEPRECATION_MESSAGE
        refund(money, authorization, options)
      end

      def status(unique_id)
        requires!(@options, :advanced_login, :advanced_password)

        post = {:unique_id => unique_id}
        add_advanced_user(post)
        add_standard_parameters('queryDR', post)

        commit(post)
      end

      # creditcard: Optional if you want to skip one or multiple stages
      #   e.g. provide a credit card with only type to skip the type stage
      # options: A hash with the following keys
      #   :locale - (e.g. en, es) to change the language of the redirected page
      #   :return_url - the URL to return to once the payment is complete
      #   :card_type - Skip the card type step. Values are ActiveMerchant format
      #                e.g. master, visa, american_express, diners_club
      def purchase_offsite_url(money, options = {})
        requires!(options, :order_id, :return_url)
        requires!(@options, :secure_hash)

        post = {}
        post[:Amount] = amount(money)
        add_invoice(post, options)
        add_creditcard_type(post, options[:card_type]) if options[:card_type]
        add_address(post, creditcard, options)
        add_customer_data(post, options)

        post.merge!(
          :Locale => options[:locale] || 'en',
          :ReturnURL => options[:return_url]
        )

        add_standard_parameters('pay', post, options)

        add_secure_hash(post)

        SERVER_HOSTED_URL + '?' + post_data(post)
      end

      private                       
      
      def add_customer_data(post, options)
      end

      def add_address(post, creditcard, options)      
      end

      def add_advanced_user(post)
        post[:User] = @options[:advanced_login]
        post[:Password] = @options[:advanced_password]
      end

      def add_invoice(post, options)
        post[:OrderInfo] = options[:order_id]
      end

      def add_creditcard(post, creditcard)      
        post[:CardNum] = creditcard.number
        post[:CardSecurityCode] = creditcard.verification_value if creditcard.verification_value?
        post[:CardExp] = format(creditcard.year, :two_digits) + format(creditcard.month, :two_digits)
      end

      def add_creditcard_type(post, card_type)
        post[:Gateway]  = 'ssl'
        post[:card] = CARD_TYPES.detect{|ct| ct.am_code == card_type}.migs_long_code
      end

      def parse(body)
        params = CGI::parse(body)
        hash = {}
        params.each do |key, value|
          hash[key.gsub('vpc_', '').to_sym] = value[0]
        end
        hash
      end     

      def commit(post)
        data = ssl_post MERCHANT_HOSTED_URL, post_data(post)

        response = parse(data)

        Response.new(success?(response), response[:Message], response,
          :test => @test,
          :authorization => response[:TransactionNo],
          :fraud_review => fraud_review?(response),
          :avs_result => { :code => response[:AVSResultCode] },
          :cvv_result => response[:CSCResultCode]
        )
      end

      def success?(response)
        response[:TxnResponseCode] == '0'
      end

      def fraud_review?(response)
        ISSUER_RESPONSE_CODES[response[:AcqResponseCode]] == 'Suspected Fraud'
      end

      def add_standard_parameters(action, post, options = {})
        post.merge!(
          :Version     => API_VERSION,
          :Merchant    => @options[:login],
          :AccessCode  => @options[:password],
          :Command     => action,
          :MerchTxnRef => options[:unique_id] || generate_unique_id.slice(0, 40)
        )
      end

      def post_data(post)
        post.collect { |key, value| "vpc_#{key}=#{CGI.escape(value.to_s)}" }.join("&")
      end

      def add_secure_hash(post)
        sorted_post = Hash[post.sort]
        input = @options[:secure_hash] + sorted_post.values.map(&:to_s).join
        
        post[:SecureHash] = Digest::MD5.hexdigest(input).upcase
      end

      def parse_offsite_response(params)
        
      end
    end
  end
end

