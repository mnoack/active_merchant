module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class MigsGateway < Gateway
      API_VERSION = 1

      SERVER_HOSTED_URL = 'https://migs.mastercard.com.au/vpcpay'
      MERCHANT_HOSTED_URL = 'https://migs.mastercard.com.au/vpcdps'

      TXN_RESPONSE_CODES = {
        '?' => 'Response Unknown',
        '0' => 'Transaction Successful',
        '1' => 'Transaction Declined - Bank Error',
        '2' => 'Bank Declined Transaction',
        '3' => 'Transaction Declined - No Reply from Bank',
        '4' => 'Transaction Declined - Expired Card',
        '5' => 'Transaction Declined - Insufficient funds',
        '6' => 'Transaction Declined - Error Communicating with Bank',
        '7' => 'Payment Server Processing Error - Typically caused by invalid input data such as an invalid credit card number. Processing errors can also occur',
        '8' => 'Transaction Declined - Transaction Type Not Supported',
        '9' => 'Bank Declined Transaction (Do not contact Bank)',
        'A' => 'Transaction Aborted',
        'C' => 'Transaction Cancelled',
        'D' => 'Deferred Transaction',
        'E' => 'Issuer Returned a Referral Response',
        'F' => '3D Secure Authentication Failed',
        'I' => 'Card Security Code Failed',
        'L' => 'Shopping Transaction Locked (This indicates that there is another transaction taking place using the same shopping transaction number)',
        'N' => 'Cardholder is not enrolled in 3D Secure (Authentication Only)',
        'P' => 'Transaction is Pending',
        'R' => 'Retry Limits Exceeded, Transaction Not Processed',
        'S' => 'Duplicate OrderInfo used. (This is only relevant for Payment Servers that enforce the uniqueness of this field)',
        'U' => 'Card Security Code Failed'
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
        'MS' => 'Maestro Card',
        'MC' => 'MasterCard',
        'PL' => 'Private Label Card',
        'VC' => 'Visa Card'
      }

      VERIFIED_3D_CODES = {
        'Y' => 'The cardholder was successfully authenticated.',
        'E' => 'The cardholder is not enrolled.',
        'N' => 'The cardholder was not verified.',
        'U' => 'The cardholder\'s Issuer was unable to authenticate due to a system error at the Issuer.',
        'F' => 'An error exists in the format of the request from the merchant. For example, the request did not contain all required fields, or the format of some fields was invalid.',
        'A' => 'Authentication of your Merchant ID and Password to the Directory Server Failed (see "What does a Payment Authentication Status of "A" mean?" on page 85).',
        'D' => 'Error communicating with the Directory Server, for example, the Payment Server could not connect to the directory server or there was a versioning mismatch.',
        'C' => 'The card type is not supported for authentication.',
        'M' => 'This indicates that attempts processing was used. Verification is marked with status M - ACS attempts processing used. Payment is performed with authentication. Attempts is when a cardholder has successfully passed the directory server but decides not to continue with the authentication process and cancels.',
        'S' => 'The signature on the response received from the Issuer could not be validated. This should be considered a failure.',
        'T' => 'ACS timed out. The Issuer\'s ACS did not respond to the Authentication request within the time out period.',
        'P' => 'Error parsing input from Issuer.',
        'I' => 'Internal Payment Server system error. This could be caused by a temporary DB failure or an error in the security module or by some error in an internal system.'
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

        commit('pay', post)
      end

      # MiGS works by merchants being either purchase only or authorize + captures
      # Where to authorize you do the same as a purchase
      alias_method :authorize, :purchase

      def capture(money, authorization, options = {})
        requires!(@options, :advanced_login, :advanced_password)

        post = options.merge(:TransNo => authorization)
        post[:Amount] = amount(money)
        add_advanced_user(post)

        commit('capture', post)
      end

      def refund(money, authorization, options = {})
        requires!(@options, :advanced_login, :advanced_password)

        post = options.merge(:TransNo => authorization)
        post[:Amount] = amount(money)
        add_advanced_user(post)

        commit('refund', post)
      end

      def credit(money, authorization, options = {})
        deprecated CREDIT_DEPRECATION_MESSAGE
        refund(money, authorization, options)
      end

      def status(unique_id)
        requires!(@options, :advanced_login, :advanced_password)

        post = {:unique_id => unique_id}
        add_advanced_user(post)

        commit('queryDR', post)
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

      def post_data(action, parameters = {})
        post = {
          :Version     => API_VERSION,
          :Merchant    => @options[:login],
          :AccessCode  => @options[:password],
          :Command     => action,
          :MerchTxnRef => parameters[:unique_id] || generate_unique_id.slice(0, 40)
        }

        request = post.merge(parameters).collect { |key, value| "vpc_#{key}=#{CGI.escape(value.to_s)}" }.join("&")
        request
      end
    end
  end
end

