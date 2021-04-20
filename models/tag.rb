class Tag < Sequel::Model
	NAME_LENGTH_MAX = 25
	NAME_WORDS_MAX = 1
  SITE_VIEWS_MINIMUM_FOR_BROWSE = 10_000
  many_to_many :sites

  def before_create
    super
    values[:name] = self.class.clean_name values[:name]
  end

  def self.clean_name(name)
    name.downcase.strip
  end

  def self.create_unless_exists(name)
    name = clean_name name
    return nil if name == '' || name.nil?
    dataset.filter(name: name).first || create(name: name)
  end

  def self.autocomplete(name, limit=3)
    DB["select tags.name,count(*) as c from sites_tags inner join tags on tags.id=sites_tags.tag_id inner join sites on sites.id=sites_tags.site_id where is_deleted='f' and is_banned='f' and is_crashing='f' and site_changed='t' and tags.is_nsfw='f' and tags.name != '' and tags.name LIKE ? group by tags.name having count(*) > 1 order by c desc LIMIT ?", name+'%', limit].all
  end

  def self.popular_names(limit=10)
		cache_key = "tag_popular_names_#{limit}".to_sym
		cache = $redis_cache.get cache_key
    if cache.nil?
      res = DB["select tags.name,count(*) as c from sites_tags inner join tags on tags.id=sites_tags.tag_id where tags.name != '' and tags.is_nsfw='f' group by tags.name having count(*) > 1 order by c desc LIMIT ?", limit].all
      $redis_cache.set cache_key, res.to_msgpack
      $redis_cache.expire cache_key, 86400 # 24 hours
    else
      res = MessagePack.unpack cache, symbolize_keys: true
    end
    res
  end
end
