Fabricator(:site) do
  username { Faker::Internet.email }
  password { 'abcde' }
end