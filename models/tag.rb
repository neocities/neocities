class Tag < Sequel::Model
	NAME_LENGTH_MAX = 25
	NAME_WORDS_MAX = 1
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
    DB["select tags.name,count(*) as c from sites_tags inner join tags on tags.id=sites_tags.tag_id where tags.name != '' and tags.name LIKE ? group by tags.name having count(*) > 1 order by c desc LIMIT ?", name+'%', limit].all
  end

  def self.popular_names(limit=10)
    DB["select tags.name,count(*) as c from sites_tags inner join tags on tags.id=sites_tags.tag_id where tags.name != '' group by tags.name having count(*) > 1 order by c desc LIMIT ?", limit].all
  end
end
