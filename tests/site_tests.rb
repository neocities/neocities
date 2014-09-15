require_relative './environment.rb'
require 'rack/test'

include Rack::Test::Methods

def app
  Sinatra::Application
end

describe Site do
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

  describe 'suggestions' do
    it 'should return suggestions for tags' do
      site = Fabricate :site, new_tags_string: 'vegetables'
      Site::SUGGESTIONS_LIMIT.times { Fabricate :site, new_tags_string: 'vegetables' }

      site.suggestions.length.must_equal Site::SUGGESTIONS_LIMIT

      site.suggestions.each {|s| s.tags.first.name.must_equal 'vegetables'}

      site = Fabricate :site, new_tags_string: 'gardening'
      (Site::SUGGESTIONS_LIMIT-5).times {
        Fabricate :site, new_tags_string: 'gardening', views: Site::SUGGESTIONS_VIEWS_MIN
      }

      site.suggestions.length.must_equal Site::SUGGESTIONS_LIMIT
    end
  end
end