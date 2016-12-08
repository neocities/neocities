Sequel.migration do
  up {
    DB['ALTER TABLE sites ADD CONSTRAINT uniqueusername UNIQUE (username)'].first
  }

  down {
  }
end
