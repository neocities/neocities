class Follow < Sequel::Model
  many_to_one :site
  many_to_one :actioning_site, :class => :Site
end