class Stat < Sequel::Model
  many_to_one :site
end