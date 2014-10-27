module Sequel::Plugins::CreateTimestamp
  module InstanceMethods
    def before_create
      self.created_at = Time.now if respond_to?(:created_at) && !self.created_at
      super
    end
  end
end