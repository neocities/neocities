# frozen_string_literal: true

class SiteIdentifierHistory < Sequel::Model
  USERNAME = 'username'
  EMAIL = 'email'
  TYPES = [USERNAME, EMAIL].freeze

  many_to_one :site

  def before_validation
    self.identifier = identifier.downcase unless identifier.nil?
    self.changed_at ||= Time.now
    super
  end

  def validate
    super
    errors.add :site_id, 'is required' if site_id.nil?
    errors.add :identifier_type, 'is invalid' unless TYPES.include?(identifier_type)
    errors.add :identifier, 'is required' if identifier.nil? || identifier.empty?
  end
end
