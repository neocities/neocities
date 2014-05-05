class CommentLike < Sequel::Model
  many_to_one :comment
  many_to_one :actioning_site, class: :Site
end
