require "spec_helper"

RSpec.describe ActiveRecordBlockMatchers do
  it "has a version number" do
    expect(ActiveRecordBlockMatchers::VERSION).not_to be nil
  end

  describe "`create_a_new` matcher" do
    it "passes if a new record of the given type was created by the block" do
      expect { Person.create! }.to create_a_new(Person)
    end

    it "fails if no record of the given type was created by the block" do
      expect {
        expect {}.to create_a_new(Person)
      }.to raise_error
    end

    it "fails if more than one record of the given type was created by the block" do
      expect {
        expect { Person.create!; Person.create! }.to create_a_new(Person)
      }.to raise_error
    end

    it "doesn't find records created before the block" do
      Person.create!
      expect {
        expect {}.to create_a_new(Person)
      }.to raise_error
    end

    it "can chain `with_attributes`" do
      expect { Person.create!(first_name: "Pam", last_name: "Greer") }
        .to create_a_new(Person)
        .with_attributes(first_name: "Pam", last_name: "Greer", full_name: "Pam Greer")
    end

    it "fails if attributes don't match" do
      expect {
        expect { Person.create!(first_name: "Pam") }
          .to create_a_new(Person)
          .with_attributes(first_name: "Sally")
      }.to raise_error
    end

    it "is aliases as `create_a`" do
      expect { Person.create! }.to create_a(Person)
    end

    it "is aliases as `create_an`" do
      expect { Person.create! }.to create_an(Person)
    end

    it "can be negated" do
      expect {}.not_to create_a(Person)
      expect {
        expect { Person.create! }.not_to create_a(Person)
      }.to raise_error
    end
  end

  describe "configuration" do
    it "allows created_at_column_name to be configured" do
      original_column_name = described_class::Config.created_at_column_name
      described_class::Config.created_at_column_name = "create_timestamp"
      begin
        expect(described_class::Config.created_at_column_name).to eq "create_timestamp"
      ensure
        described_class::Config.created_at_column_name = original_column_name
      end
    end
  end
end
