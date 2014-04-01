Fabricator(:site) do
  username { SecureRandom.hex }
  password { 'abcde' }
end