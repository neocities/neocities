class Tag < Sequel::Model
  many_to_many :sites
end