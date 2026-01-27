# frozen_string_literal: true

require "spec_helper"

RSpec.describe "`create_associated` matcher" do
  let(:person) { Person.create!(first_name: "Jane", last_name: "Doe") }

  it "passes if a new record was created within the given scope" do
    expect { person.pets.create!(name: "Rex") }.to create_associated(person.pets)
  end

  it "passes when using hash form with expected count" do
    expect {
      person.pets.create!(name: "Rex")
      person.pets.create!(name: "Fido")
    }.to create_associated(person.pets => 2)
  end

  it "passes when using scope as sole argument (expects 1)" do
    expect { person.pets.create!(name: "Buddy") }.to create_associated(person.pets)
  end

  it "fails when nothing is created within the scope" do
    expect {
      expect {}.to create_associated(person.pets)
    }.to raise_error(/The block should have created 1 Pet within the scope, but created 0/)
  end

  it "does not count records created in other associations" do
    other = Person.create!(first_name: "Other", last_name: "User")
    expect {
      expect { other.pets.create!(name: "Other") }.to create_associated(person.pets)
    }.to raise_error(/The block should have created 1 Pet within the scope, but created 0/)
  end

  it "does not count records created before the block" do
    person.pets.create!(name: "existing")
    expect {
      expect {}.to create_associated(person.pets => 1)
    }.to raise_error(/The block should have created 1 Pet within the scope, but created 0/)
  end

  it "fails when too few records are created" do
    expect {
      expect { person.pets.create!(name: "only one") }.to create_associated(person.pets => 2)
    }.to raise_error(/The block should have created 2 Pets within the scope, but created 1/)
  end

  it "fails when too many records are created" do
    expect {
      expect {
        person.pets.create!(name: "a")
        person.pets.create!(name: "b")
      }.to create_associated(person.pets)
    }.to raise_error(/The block should have created 1 Pet within the scope, but created 2/)
  end

  it "can be negated" do
    expect {}.not_to create_associated(person.pets)
    expect { person.pets.create!(name: "x") }.not_to create_associated(person.pets => 2)
  end

  it "fails when negated if the expected count was created" do
    expect {
      expect { person.pets.create!(name: "v") }.not_to create_associated(person.pets)
    }.to raise_error(/The block should not have created 1 Pet within the scope, but created 1/)
  end

  it "can chain `with_attributes` (single hash for single record)" do
    expect {
      person.pets.create!(name: "Whiskers", person_id: person.id)
    }.to create_associated(person.pets).with_attributes(name: "Whiskers")
  end

  it "can chain `with_attributes` with array of hashes for multiple records" do
    expect {
      person.pets.create!(name: "first")
      person.pets.create!(name: "second")
    }.to create_associated(person.pets => 2).with_attributes([{ name: "first" }, { name: "second" }])
  end

  it "can chain `with_attributes` with scope-keyed hash for multiple scopes" do
    other = Person.create!(first_name: "Other", last_name: "User")
    expect {
      person.pets.create!(name: "mine")
      other.pets.create!(name: "theirs")
    }.to create_associated(person.pets => 1, other.pets => 1).with_attributes(
      person.pets => [{ name: "mine" }],
      other.pets => [{ name: "theirs" }]
    )
  end

  it "fails if expected attributes do not match" do
    expect {
      expect {
        person.pets.create!(name: "actual")
      }.to create_associated(person.pets).with_attributes(name: "expected")
    }.to raise_error(/Missing 1 Pet with these attributes/)
  end

  it "uses composable matchers for comparing attributes" do
    expect {
      person.pets.create!(name: "Spot")
    }.to create_associated(person.pets).with_attributes(name: a_string_starting_with("S"))
  end

  it "raises if attribute count does not match expected record count" do
    expect {
      expect { person.pets.create!(name: "x") }
        .to create_associated(person.pets => 2)
        .with_attributes([{ name: "x" }])
    }.to raise_error(ArgumentError, /Specified the block should create 2 Pet within the scope, but provided 1 attribute specifications/)
  end

  it "can chain `which` with a block that receives new records by klass" do
    block_called = false
    expect {
      person.pets.create!(name: "snapshot")
    }.to create_associated(person.pets).which { |records_by_klass|
      expect(records_by_klass[Pet]).to be_present
      expect(records_by_klass[Pet].first.name).to eq "snapshot"
      block_called = true
    }
    expect(block_called).to be true
  end

  it "can chain `and_return_it` when expecting a single record" do
    expect {
      person.pets.create!(name: "Rex")
    }.to create_associated(person.pets).with_attributes(name: "Rex").and_return_it
  end

  it "verifies block return value when using `and_return_it`" do
    created = nil
    expect {
      expect {
        created = person.pets.create!(name: "Rex")
        "wrong"
      }.to create_associated(person.pets).and_return_it
    }.to raise_error(/Expected the block to return the created Pet, but it returned/)
    expect(created).to be_present

    expect {
      expect { person.pets.create!(name: "Fido"); nil }.to create_associated(person.pets).and_return_it
    }.to raise_error(/Expected the block to return the created Pet/)
  end

  it "passes when block returns the created record and `and_return_it` is used" do
    result = nil
    expect {
      result = person.pets.create!(name: "returned")
    }.to create_associated(person.pets).and_return_it
    expect(result).to eq person.pets.last
  end

  it "can chain `and_return_them` for multiple records" do
    result = nil
    expect {
      result = [
        person.pets.create!(name: "a"),
        person.pets.create!(name: "b")
      ]
    }.to create_associated(person.pets => 2).and_return_them
    expect(result.map(&:name)).to contain_exactly("a", "b")
  end

  it "raises when `and_return_it` is used but multiple records are expected" do
    expect {
      create_associated(person.pets => 2).and_return_it
    }.to raise_error(ArgumentError, /`and_return_it` only applies when expecting exactly one record/)
  end

  it "explains if records were created but `which` block raised" do
    error = capture_error do
      expect { person.pets.create!(name: "x") }.to create_associated(person.pets)
        .which { |records| expect(records[Pet].first.name).to eq "y" }
    end
    expect(error.message).to match(/expected: "y"\s+got: "x"/m)
  end
end
