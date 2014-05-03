class Comment < Sequel::Model
  include Sequel::ParanoidDelete
  many_to_one :event
  many_to_one :actioning_site, class: :Site
end