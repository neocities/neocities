require_relative './environment.rb'

describe Tag do
  describe 'creation' do
    it 'should force downcase' do
      Tag.where(name: 'derp').delete
      Tag.create_unless_exists 'derp'
      Tag[name: 'derp'].wont_be_nil
      Tag.create_unless_exists 'DERP'
      Tag.filter(name: 'DERP').count.must_equal 0
      Tag.filter(name: 'derp').count.must_equal 1
    end

    it 'prohibits junk tags' do
      Tag.where(name: '').delete
      tag = Tag.create_unless_exists ''
      Tag.where(name: '').count.must_equal 0
    end

    it 'strips tags' do
      badname = '  derp  '
      Tag.where(name: 'derp').delete
      Tag.create_unless_exists badname
      Tag[name: badname].must_be_nil
      Tag[name: badname.strip].wont_be_nil
    end

    it 'does not duplicate' do
      name = SecureRandom.hex(4).upcase
      2.times { Tag.create_unless_exists 'DERP' }
      Tag.where(name: 'DERP').count.must_equal 0
      Tag.where(name: 'derp').count.must_equal 1
    end
  end
end