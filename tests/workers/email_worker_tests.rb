require_relative '../environment.rb'

describe EmailWorker do
  before do
    Mail::TestMailer.deliveries.clear
  end

  it 'sends an email' do
    worker = EmailWorker.new
    worker.perform({
      'from'    => 'from@example.com',
      'to'      => 'to@example.com',
      'subject' => 'Hello World',
      'body'    => 'testing'
    })

    mail = Mail::TestMailer.deliveries.first
    mail.from.first.must_equal 'from@example.com'
    mail.to.first.must_equal 'to@example.com'
    mail.subject.must_equal 'Hello World'
    body = mail.body.to_s
    puts body
    body.must_match /testing/
    body.must_match /unsubscribe/
  end
end