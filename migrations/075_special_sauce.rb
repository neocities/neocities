# IT'S MADE OUT OF FUCKING PEOPLE

Sequel.migration do
  up {
    DB.add_column :sites, :score, :integer
  }

  down {
    DB.drop_column :sites, :score
  }
end
