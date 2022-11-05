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
    _(mail.from.first).must_equal 'from@example.com'
    _(mail.to.first).must_equal 'to@example.com'
    _(mail.subject).must_equal 'Hello World'
    body = mail.body.to_s
    _(body).must_match /testing/
    _(body).must_match /unsubscribe/
  end

  it 'sends an email without a footer' do
    worker = EmailWorker.new
    worker.perform({
      'no_footer' => true,
      'from'      => 'from@example.com',
      'to'        => 'to@example.com',
      'subject'   => 'Hello World',
      'body'      => 'testing'
    })
    body = Mail::TestMailer.deliveries.first.body.to_s
    _(body).must_match /testing/
    _(body).wont_match /unsubscribe/
  end
end
