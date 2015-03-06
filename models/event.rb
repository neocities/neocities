class Event < Sequel::Model
  include Sequel::ParanoidDelete

  many_to_one :site
  many_to_one :follow
  one_to_one  :tip
  one_to_one  :tag
  many_to_one :site_change
  many_to_one :profile_comment
  one_to_many :likes
  one_to_many :comments
  many_to_one :site
  many_to_one :actioning_site, key: :actioning_site_id, class: :Site

  DEFAULT_GLOBAL_LIMIT = 200
  GLOBAL_VIEWS_MINIMUM = 500

  def self.global_dataset(current_page=1, limit=DEFAULT_GLOBAL_LIMIT)
    select_all(:events).
      order(:created_at.desc).
      paginate(current_page, 100).
      join_table(:inner, :sites, id: :site_id).
      exclude(Sequel.qualify(:sites, :is_deleted) => false).
      exclude(is_nsfw: false).
      exclude(is_banned: false).
      exclude(is_crashing: false).
      where{views > GLOBAL_VIEWS_MINIMUM}.
      or(site_change_id: nil)
  end

  def created_by?(site)
    return true if actioning_site_id == site.id
    false
  end

  def liking_site_titles
    likes_dataset.select(:actioning_site_id).all.collect do |like|
      like.actioning_site_dataset.select(:domain,:title,:username).first.title
    end
  end

  def liking_site_usernames
    likes_dataset.select(:actioning_site_id).all.collect do |like|
      like.actioning_site_dataset.select(:username).first.username
    end
  end

  def add_site_comment(site, message)
    add_comment actioning_site_id: site.id, message: message
  end

  def site_likes?(site)
    likes_dataset.filter(actioning_site_id: site.id).count > 0
  end

  def site_like(site)
    add_like actioning_site_id: site.id
  end

  def site_unlike(site)
    likes_dataset.filter(actioning_site_id: site.id).delete
  end

  def toggle_site_like(site)
    if site_likes? site
      site_unlike site
      false
    else
      site_like site
      true
    end
  end
end
