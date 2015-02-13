module Sequel
  module ParanoidDelete

    def self.included(base)
      base.extend(ClassMethods)
    end

    # Instead of actually deleting, we just set is_deleted to true,
    # and look for it with our default dataset filter.
    def delete
      self.is_deleted = true
      save :validate => false
      true
    end

    module ClassMethods

      # There's no hook for setting default filters after inheritance (that I'm aware of),
      # so this adds the filter for the first time the class' dataset is accessed for the new model.
      def dataset
        if @_is_deleted_filter_set.nil?
          #KD: I turned this off because I think it's easier to do this manually.
          #@dataset.filter! is_deleted: false
          @_is_deleted_filter_set = true
        end
        super
      end

    end
  end

  # Model.include ParanoidDelete
end