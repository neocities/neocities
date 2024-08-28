# frozen_string_literal: true
class Event < Sequel::Model
  include Sequel::ParanoidDelete

  many_to_one :site
  many_to_one :follow
  many_to_one :tip
  one_to_one  :tag
  many_to_one :site_change
  many_to_one :profile_comment
  one_to_many :likes
  one_to_many :comments, order: :created_at
  many_to_one :site
  many_to_one :actioning_site, key: :actioning_site_id, class: :Site

  PAGINATION_LENGTH = 10
  GLOBAL_PAGINATION_LENGTH = 20
  GLOBAL_SCORE_LIMIT = 2

  def undeleted_comments_count
    comments_dataset.exclude(is_deleted: true).count
  end

  def undeleted_comments(exclude_ids=nil)
    ds = comments_dataset.exclude(is_deleted: true).order(:created_at)
    if exclude_ids
      ds = ds.exclude actioning_site_id: exclude_ids
    end
    ds.all
  end

  def self.news_feed_default_dataset
    select(:events.*).
    join(:sites, id: :site_id).
    left_join(Sequel[:sites].as(:actioning_sites), id: :events__actioning_site_id).
    order(:events__created_at.desc).
    exclude(events__is_deleted: true).
    exclude(sites__is_deleted: true).
    exclude(sites__is_nsfw: true).
    exclude(sites__is_crashing: true).
    exclude(actioning_sites__is_deleted: true).
    where(follow_id: nil)
  end

  def self.global_dataset
    news_feed_default_dataset.where(
      Sequel.expr(Sequel[:sites][:score] > GLOBAL_SCORE_LIMIT) |
      Sequel.expr(Sequel[:actioning_sites][:score] > GLOBAL_SCORE_LIMIT)
    )
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

  def name
    return 'follow' if follow_id
    return 'tip' if tip_id
    return 'tag' if tag_id
    return 'site change' if site_change_id
    return 'comment' if profile_comment_id
  end
end
