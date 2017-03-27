class Event < Sequel::Model
  include Sequel::ParanoidDelete

  many_to_one :site
  many_to_one :follow
  many_to_one  :tip
  one_to_one  :tag
  many_to_one :site_change
  many_to_one :profile_comment
  one_to_many :likes
  one_to_many :comments, order: :created_at
  many_to_one :site
  many_to_one :actioning_site, key: :actioning_site_id, class: :Site

  DEFAULT_GLOBAL_LIMIT = 300
  GLOBAL_VIEWS_MINIMUM = 5
  GLOBAL_VIEWS_SITE_CHANGE_MINIMUM = 1000

  def self.news_feed_default_dataset
    select_all(:events).
      order(:created_at.desc).
      join_table(:inner, :sites, id: :site_id).
      exclude(Sequel.qualify(:sites, :is_deleted) => true).
      exclude(Sequel.qualify(:events, :is_deleted) => true).
      exclude(Sequel.qualify(:sites, :is_nsfw) => true).
      exclude(is_banned: true)
  end

  def self.global_dataset(current_page=1, limit=DEFAULT_GLOBAL_LIMIT)
    news_feed_default_dataset.
      paginate(current_page, 100).
      exclude(is_nsfw: true).
      exclude(is_crashing: true).
      where{views > GLOBAL_VIEWS_MINIMUM}.
      where(site_change_id: nil)
  end

  def self.global_site_changes_dataset
    news_feed_default_dataset.
      where{views > GLOBAL_VIEWS_SITE_CHANGE_MINIMUM}.
      exclude(is_nsfw: true).
      exclude(is_crashing: true).
      exclude(site_change_id: nil)
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
