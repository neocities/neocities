class Event < Sequel::Model
  many_to_one :site
  one_to_one  :follow
  one_to_one  :tip
  one_to_one  :tag
  one_to_one  :site_change
  many_to_one :profile_comment
  one_to_many :likes
end