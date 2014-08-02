Fabricator(:site) do
  username { SecureRandom.hex }
  password { 'abcde' }
  email    { SecureRandom.uuid.gsub('-', '')+'@example.com' }
end