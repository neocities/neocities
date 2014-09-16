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

    it 'prohibits junk tags' do
      Tag.where(name: '').delete
      tag = Tag.create_unless_exists ''
      Tag.where(name: '').count.must_equal 0
    end

    it 'strips tags' do
      name = SecureRandom.hex(4)+'  '
      Tag.create_unless_exists name

      Tag[name: name.strip].wont_be_nil
    end

    it 'does not duplicate' do
      name = SecureRandom.hex(4).upcase
      2.times { Tag.create_unless_exists name }
      Tag.where(name: name.downcase).count.must_equal 1
    end
  end
end