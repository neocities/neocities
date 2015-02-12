require_relative './environment.rb'

def app
  Sinatra::Application
end

describe Site do
  describe 'destroy' do
    it 'should delete events properly' do
      site_commented_on = Fabricate :site
      site_commenting = Fabricate :site
      site_commented_on.add_profile_comment actioning_site_id: site_commenting.id, message: 'hi'
      site_commented_on.events_dataset.count.must_equal 1
      site_commenting.destroy
      site_commented_on.events_dataset.count.must_equal 0
    end
  end

  describe 'can_email' do
    it 'should fail if send_emails is false' do
      site = Fabricate :site
      site.can_email?.must_equal true
      site.update send_emails: false
      site.can_email?.must_equal false
      site.can_email?(:send_comment_emails).must_equal false
      site.update send_emails: true
      site.can_email?(:send_comment_emails).must_equal true
      site.update send_comment_emails: false
      site.can_email?(:send_comment_emails).must_equal false
    end
  end

  describe 'send_email' do
    before do
      EmailWorker.jobs.clear
      @site = Fabricate :site
    end

    it 'works' do
      @site.send_email(subject: 'Subject', body: 'Body')
      EmailWorker.jobs.length.must_equal 1
      args = EmailWorker.jobs.first['args'].first
      args['from'].must_equal Site::FROM_EMAIL
      args['to'].must_equal @site.email
      args['subject'].must_equal 'Subject'
      args['body'].must_equal 'Body'
    end

    it 'fails if send_emails is false' do
      @site.update send_emails: false
      @site.send_email(subject: 'Subject', body: 'Body')
    end
  end

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