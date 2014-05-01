class Event < Sequel::Model
  many_to_one :site
  one_to_one  :follow
  one_to_one  :tip
  one_to_one  :tag
  one_to_one  :site_change
  many_to_one :profile_comment
  one_to_many :likes
  
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