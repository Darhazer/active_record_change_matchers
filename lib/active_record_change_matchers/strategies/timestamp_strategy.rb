module ActiveRecordChangeMatchers
  class TimestampStrategy

    def initialize(block)
      @block = block
    end

    def new_records(classes)
      time_before = Time.current

      existing_records = classes.each_with_object({}) do |klass, hash|
        hash[klass] = klass.where("#{column_name} = ?", time_before).to_a
      end

      block.call

      classes.each_with_object({}) do |klass, new_records|
        new_records[klass] = klass.where("#{column_name} > ?", time_before).to_a +
        new_records[klass] += klass.where("#{column_name} = ?", time_before).where.not(klass.primary_key => existing_records[klass]).to_a
      end
    end

    private

    attr_reader :block

    def column_name
      @column_name ||= ActiveRecordChangeMatchers::Config.created_at_column_name
    end
    
  end
end
