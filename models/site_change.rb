class SiteChange < Sequel::Model
  many_to_one :site
  one_to_one  :event
end