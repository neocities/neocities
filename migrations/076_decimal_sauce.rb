# IT'S MADE OUT OF FUCKING DECIMAL PEOPLE

Sequel.migration do
  up {
    DB.drop_column :sites, :score
    DB.add_column :sites, :score, :decimal, default: 0
  }

  down {
    DB.drop_column :sites, :score
    DB.add_column :sites, :score, :integer
  }
end
