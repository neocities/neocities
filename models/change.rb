class Change < Sequel::Model
  many_to_one :site
end