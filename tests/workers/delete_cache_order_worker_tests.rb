require_relative '../environment.rb'

describe DeleteCacheWorker do
  before do
    PurgeCacheOrderWorker.jobs.clear
    PurgeCacheWorker.jobs.clear
  end

  it 'queues up purges' do
    DeleteCacheOrderWorker.new.perform('kyledrake', '/test.jpg')

    job_one_args = DeleteCacheWorker.jobs.first['args']
    job_two_args = DeleteCacheWorker.jobs.last['args']
    job_one_args[0].must_equal '10.0.0.1'
    job_one_args[1].must_equal 'kyledrake'
    job_one_args[2].must_equal '/test.jpg'
    job_two_args[0].must_equal '10.0.0.2'
    job_two_args[1].must_equal 'kyledrake'
    job_two_args[2].must_equal '/test.jpg'
  end
end
