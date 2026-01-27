class CreatePets < ActiveRecord::Migration[6.0]
  def change
    create_table :pets do |t|
      t.references :person, null: false, foreign_key: true
      t.string :name
      t.timestamps
    end
  end
end
