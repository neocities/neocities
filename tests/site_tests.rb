require_relative './environment.rb'
require 'rack/test'

include Rack::Test::Methods

def app
  Sinatra::Application
end

describe 'site' do
  describe 'plan_name' do
    it 'should set to free for missing stripe_customer_id' do
      site = Fabricate :site
      site.reload.plan_type.must_equal 'free'
    end

    it 'should be free for no plan_type entry' do
      site = Fabricate :site, stripe_customer_id: 'cust_derp'
      site.plan_type.must_equal 'free'
    end

    it 'should match plan_type' do
      %w{supporter neko catbus fatcat}.each do |plan_type|
        site = Fabricate :site, plan_type: plan_type
        site.plan_type.must_equal plan_type
      end
    end
  end
end