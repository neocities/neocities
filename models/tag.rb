class Tag < Sequel::Model
	NAME_LENGTH_MAX = 25
	NAME_WORDS_MAX = 1
  many_to_many :sites

  def before_create
    super
    values[:name].downcase!
  end

  def self.create_unless_exists(name)
    dataset.filter(name: name).first || create(name: name)
  end

  def self.suggestions(name, limit=3)
    Tag.filter(name: /^#{name}/i).
    order(:name).
    limit(limit).
    all
  end

  def self.popular_names(limit=10)
    DB["select tags.name,count(*) as c from sites_tags inner join tags on tags.id=sites_tags.tag_id where tags.name != '' group by tags.name having count(*) > 1 order by c desc LIMIT ?", limit].all
  end
end
