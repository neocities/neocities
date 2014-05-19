class Tag < Sequel::Model
  many_to_many :sites

  def before_create
    super
    values[:name].downcase!
  end

  def self.create_unless_exists(name)
    dataset.filter(name: name).first || create(name: name)
  end
end
