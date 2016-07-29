Fabricator(:site) do
  username        { SecureRandom.hex }
  password        { 'abcde' }
  email           { SecureRandom.uuid.gsub('-', '')+'@examplesdlfjdslfj.com' }
  email_confirmed { true }
end
