# frozen_string_literal: true

require 'net/https'
require 'uri'

class PayPalRecurring
  API_VERSION = '72.0'
  USER_AGENT = 'Neocities PayPalRecurring'

  ENDPOINTS = {
    sandbox: {
      api:  'https://api-3t.sandbox.paypal.com/nvp',
      site: 'https://www.sandbox.paypal.com/cgi-bin/webscr'
    },
    production: {
      api:  'https://api-3t.paypal.com/nvp',
      site: 'https://www.paypal.com/cgi-bin/webscr'
    }
  }.freeze

  ACTIONS = {
    cancel:     'Cancel',
    suspend:    'Suspend',
    reactivate: 'Reactivate'
  }.freeze

  INITIAL_AMOUNT_ACTIONS = {
    cancel:   'CancelOnFailure',
    continue: 'ContinueOnFailure'
  }.freeze

  OUTSTANDING = {
    next_billing: 'AddToNextBilling',
    no_auto:      'NoAutoBill'
  }.freeze

  PERIOD = {
    daily:   'Day',
    weekly:  'Weekly',
    monthly: 'Month',
    yearly:  'Year'
  }.freeze

  class << self
    attr_accessor :sandbox
    attr_accessor :username
    attr_accessor :password
    attr_accessor :signature

    def configure
      yield self
    end

    def sandbox?
      sandbox == true
    end

    def environment
      sandbox? ? :sandbox : :production
    end

    def api_endpoint
      ENDPOINTS[environment][:api]
    end

    def site_endpoint
      ENDPOINTS[environment][:site]
    end
  end

  attr_accessor :amount
  attr_accessor :cancel_url
  attr_accessor :currency
  attr_accessor :description
  attr_accessor :email
  attr_accessor :failed
  attr_accessor :frequency
  attr_accessor :initial_amount
  attr_accessor :initial_amount_action
  attr_accessor :ipn_url
  attr_accessor :locale
  attr_accessor :outstanding
  attr_accessor :payer_id
  attr_accessor :period
  attr_accessor :profile_id
  attr_accessor :reference
  attr_accessor :return_url
  attr_accessor :start_at
  attr_accessor :token
  attr_accessor :trial_amount
  attr_accessor :trial_frequency
  attr_accessor :trial_length
  attr_accessor :trial_period

  def initialize(options={})
    options.each { |name, value| public_send("#{name}=", value) }
  end

  def checkout
    run('SetExpressCheckout', billing_agreement_params.merge(
      'RETURNURL' => return_url,
      'CANCELURL' => cancel_url,
      'LOCALECODE' => build_locale(locale),
      'PAYMENTREQUEST_0_PAYMENTACTION' => 'Authorization',
      'NOSHIPPING' => 1,
      'L_BILLINGTYPE0' => 'RecurringPayments'
    ))
  end

  def request_payment
    run('DoExpressCheckoutPayment', billing_agreement_params.merge(
      'RETURNURL' => return_url,
      'CANCELURL' => cancel_url,
      'PAYMENTREQUEST_0_PAYMENTACTION' => 'Sale',
      'PAYERID' => payer_id,
      'TOKEN' => token,
      'PROFILEREFERENCE' => reference,
      'PAYMENTREQUEST_0_CUSTOM' => reference,
      'PAYMENTREQUEST_0_INVNUM' => reference
    ))
  end

  def create_recurring_profile
    run('CreateRecurringPaymentsProfile', billing_agreement_params.merge(
      'INITAMT' => initial_amount,
      'FAILEDINITAMTACTION' => map(INITIAL_AMOUNT_ACTIONS, initial_amount_action),
      'PAYERID' => payer_id,
      'TOKEN' => token,
      'PROFILEREFERENCE' => reference,
      'PROFILESTARTDATE' => build_timestamp(start_at),
      'MAXFAILEDPAYMENTS' => failed,
      'AUTOBILLOUTAMT' => map(OUTSTANDING, outstanding),
      'BILLINGFREQUENCY' => frequency,
      'BILLINGPERIOD' => map(PERIOD, period),
      'EMAIL' => email,
      'TRIALTOTALBILLINGCYCLES' => trial_length,
      'TRIALBILLINGPERIOD' => map(PERIOD, trial_period),
      'TRIALBILLINGFREQUENCY' => trial_frequency,
      'TRIALAMT' => trial_amount
    ))
  end

  def cancel
    run('ManageRecurringPaymentsProfileStatus', {
      'ACTION' => map(ACTIONS, :cancel),
      'PROFILEID' => profile_id
    })
  end

  private

  def billing_agreement_params
    {
      'PAYMENTREQUEST_0_AMT' => amount,
      'AMT' => amount,
      'PAYMENTREQUEST_0_CURRENCYCODE' => currency,
      'CURRENCYCODE' => currency,
      'DESC' => description,
      'PAYMENTREQUEST_0_DESC' => description,
      'L_BILLINGAGREEMENTDESCRIPTION0' => description,
      'PAYMENTREQUEST_0_NOTIFYURL' => ipn_url,
      'NOTIFYURL' => ipn_url
    }
  end

  def run(method, params)
    Response.new(post(default_params.merge(params).merge('METHOD' => method)))
  end

  def post(params)
    uri = URI(self.class.api_endpoint)
    request = Net::HTTP::Post.new(uri.request_uri)
    request['User-Agent'] = USER_AGENT
    request.set_form_data compact_params(params)

    http_client(uri).request(request)
  end

  def http_client(uri)
    Net::HTTP.new(uri.host, uri.port).tap do |http|
      http.use_ssl = uri.scheme == 'https'
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER if http.use_ssl?
      http.cert_store = OpenSSL::X509::Store.new if http.use_ssl?
      http.cert_store&.set_default_paths
    end
  end

  def default_params
    {
      'USER' => self.class.username,
      'PWD' => self.class.password,
      'SIGNATURE' => self.class.signature,
      'VERSION' => API_VERSION
    }
  end

  def compact_params(params)
    params.reject { |_name, value| value.nil? }
  end

  def build_locale(value)
    value.to_s.upcase if value
  end

  def build_timestamp(value)
    value.respond_to?(:to_time) ? value.to_time.utc.strftime('%Y-%m-%dT%H:%M:%SZ') : value
  end

  def map(mapping, value)
    return nil if value.nil?

    mapping.fetch(value.to_sym, value)
  end

  class Response
    attr_reader :http_response

    def initialize(http_response)
      @http_response = http_response
    end

    def params
      @params ||= URI.decode_www_form(http_response.body.to_s).each_with_object({}) do |(name, value), parsed|
        parsed[name] = value
      end
    end

    def token
      params['TOKEN']
    end

    def ack
      params['ACK']
    end

    def profile_id
      params['PROFILEID']
    end

    def checkout_url
      "#{PayPalRecurring.site_endpoint}?#{URI.encode_www_form(
        cmd: '_express-checkout',
        token: token,
        useraction: 'commit'
      )}"
    end

    def completed?
      params['PAYMENTINFO_0_PAYMENTSTATUS'] == 'Completed'
    end

    def approved?
      params['PAYMENTINFO_0_ACK'] == 'Success'
    end

    def success?
      ack == 'Success'
    end

    def valid?
      errors.empty? && success?
    end

    def errors
      @errors ||= begin
        index = 0
        [].tap do |results|
          while params["L_ERRORCODE#{index}"]
            results << {
              code: params["L_ERRORCODE#{index}"],
              messages: [
                params["L_SHORTMESSAGE#{index}"],
                params["L_LONGMESSAGE#{index}"]
              ]
            }
            index += 1
          end
        end
      end
    end
  end
end
