class Event < Sequel::Model
  many_to_one :site
  many_to_one :follow
  many_to_one :tip
  many_to_one :tag
  many_to_one :changes
  one_to_many :likes
  one_to_many :comments
end