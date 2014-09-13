require_relative './environment.rb'

describe Tag do
  describe 'creation' do
    it 'should force downcase' do
      tag_name = SecureRandom.hex(10).downcase
      Tag.create_unless_exists tag_name
      Tag[name: tag_name].wont_be_nil
      Tag.create_unless_exists tag_name.upcase
      Tag.filter(name: tag_name).count.must_equal 1
    end
  end
end