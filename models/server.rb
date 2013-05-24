class Server < Sequel::Model
  one_to_many :sites

  def self.with_slots_available
    where{slots_available > 0}.first
  end
end