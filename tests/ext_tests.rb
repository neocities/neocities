require_relative './environment.rb'

describe Time do
  describe 'ago' do
    it 'should return the modified value' do
      Time.now.ago.must_equal 'just now'
    end
  end
end