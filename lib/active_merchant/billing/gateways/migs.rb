module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class MigsGateway < Gateway
      API_VERSION = 1
      
      SERVER_HOSTED_URL = 'https://migs.mastercard.com.au/vpcpay'
      MERCHANT_HOSTED_URL = 'https://migs.mastercard.com.au/vpcdps'
      
      TXN_RESPONSE_CODES = {
        '0' => 'Transaction approved',
        '1' => 'Transaction could not be processed',
        '2' => 'Transaction declined - contact issuing bank',
        '3' => 'No reply from Processing Host',
        '4' => 'Card has expired',
        '5' => 'Insufficient credit',
        '6' => 'Error Communicating with Bank',
        '7' => 'Message Detail Error',
        '8' => 'Transaction declined - transaction type not supported',
        '9' => 'Bank Declined Transaction - Do Not Contact Bank'
      }
      
      ISSUER_RESPONSE_CODES = {
        '00' => 'Approved',
        '01' => 'Refer to Card Issuer',
        '02' => 'Refer to Card Issuer',
        '03' => 'Invalid Merchant',
        '04' => 'Pick Up Card',
        '05' => 'Do Not Honor',
        '07' => 'Pick Up Card',
        '12' => 'Invalid Transaction',
        '14' => 'Invalid Card Number (No such Number)',
        '15' => 'No Such Issuer',
        '33' => 'Expired Card',
        '34' => 'Suspected Fraud',
        '36' => 'Restricted Card',
        '39' => 'No Credit Account',
        '41' => 'Card Reported Lost',
        '43' => 'Stolen Card',
        '51' => 'Insufficient Funds',
        '54' => 'Expired Card',
        '57' => 'Transaction Not Permitted',
        '59' => 'Suspected Fraud',
        '62' => 'Restricted Card',
        '65' => 'Exceeds withdrawal frequency limit',
        '91' => 'Cannot Contact Issuer'
      }
      
      CARD_TYPE_CODES = {
        'AE' => 'American Express',
        'DC' => 'Diners Club',
        'JC' => 'JCB Card',
        'MC' => 'MasterCard',
        'VC' => 'Visa Card'
      }
      
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

        commit('pay', post)
      end

      # MiGS works by merchants being either purchase only or authorize + captures
      # Where to authorize you do the same as a purchase
      alias_method :authorize, :purchase

      def capture(money, authorization, options = {})
        requires!(options, :advanced_login, :advanced_password)

        post = options.merge(:TransNo => authorization)
        post[:Amount] = amount(money)
        add_advanced_user(post, options)

        commit('capture', post)
      end

      def refund(money, authorization, options = {})
        requires!(options, :advanced_login, :advanced_password)

        post = options.merge(:TransNo => authorization)
        post[:Amount] = amount(money)
        add_advanced_user(post, options)

        commit('refund', post)
      end

      def search(options = {})
        requires!(options, :advanced_login, :advanced_password)

        post = options
        add_ama_user(post, options)

        commit('queryDR', post)
      end

      private                       
      
      def add_customer_data(post, options)
      end

      def add_address(post, creditcard, options)      
      end

      def add_advanced_user(post, options)
        post[:User] = options[:advanced_login]
        post[:Password] = options[:advanced_password]
      end

      def add_invoice(post, options)
        post[:OrderInfo] = options[:order_id]
      end

      def add_creditcard(post, creditcard)      
        post[:CardNum] = creditcard.number
        post[:CardSecurityCode] = creditcard.verification_value if creditcard.verification_value?
        post[:CardExp] = format(creditcard.year, :two_digits) + format(creditcard.month, :two_digits)
      end

      def parse(body)
        params = CGI::parse(body)
        hash = {}
        params.each do |key, value|
          hash[key.gsub('vpc_', '').to_sym] = value[0]
        end
        hash
      end     

      def commit(action, parameters)
        data = ssl_post MERCHANT_HOSTED_URL, post_data(action, parameters)

        response = parse(data)

        Response.new(success?(response), response[:Message], response,
          :authorization => response[:TransactionNo],
          :transaction_response => TXN_RESPONSE_CODES[response[:TxnResponseCode]],
          :issuer_response      => ISSUER_RESPONSE_CODES[response[:AcqResponseCode]]
        )
      end

      def success?(response)
        response[:TxnResponseCode] == '0'
      end
      
      def post_data(action, parameters = {})
        post = {
          :Version     => API_VERSION,
          :Merchant    => @options[:login],
          :AccessCode  => @options[:password],
          :Command     => action,
          :MerchTxnRef => @options[:unique_id] || generate_unique_id.slice(0, 40)
        }

        request = post.merge(parameters).collect { |key, value| "vpc_#{key}=#{CGI.escape(value.to_s)}" }.join("&")
        request
      end
    end
  end
end

