require_relative './environment.rb'
require 'rack/test'

include Rack::Test::Methods

def app
  Sinatra::Application
end

describe 'email blasting' do
  before do
    EmailWorker.jobs.clear
    @admin_site = Fabricate :site, is_admin: true
  end

  it 'works' do
    DB['update sites set changed_count=?', 0].first
    relevant_emails = []

    sites_emailed_count = Site::EMAIL_BLAST_MAXIMUM_PER_DAY*2

    sites_emailed_count.times {
      site = Fabricate :site, updated_at: Time.now, changed_count: 1
      relevant_emails << site.email
    }

    EmailWorker.jobs.clear

    time = Time.now

    Timecop.freeze(time) do
      post '/admin/email', {
        :csrf_token => 'abcd',
        :subject => 'Subject Test',
        :body => 'Body Test'}, {
        'rack.session' => { 'id' => @admin_site.id, '_csrf_token' => 'abcd' }
      }

      relevant_jobs = EmailWorker.jobs.select{|j| relevant_emails.include?(j['args'].first['to']) }
      relevant_jobs.length.must_equal sites_emailed_count

      relevant_jobs.each do |job|
        args = job['args'].first
        args['from'].must_equal 'noreply@neocities.org'
        args['subject'].must_equal 'Subject Test'
        args['body'].must_equal 'Body Test'
      end

      immediate_emails = relevant_jobs.select {|j| j['at'].nil? || j['at'] == Time.now.to_f}
      immediate_emails.length.must_equal Site::EMAIL_BLAST_MAXIMUM_PER_DAY

      tomorrows_emails = relevant_jobs.select {|j| j['at'] == (time+1.day.to_i).to_f}
      tomorrows_emails.length.must_equal Site::EMAIL_BLAST_MAXIMUM_PER_DAY
    end
  end
end
