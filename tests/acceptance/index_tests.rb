require_relative './environment.rb'

describe 'index' do
  include Capybara::DSL
  it 'goes to signup' do
    Capybara.reset_sessions!
    visit '/'
    click_button 'Create My Website'
    page.must_have_content('Create a New Website')
  end
end