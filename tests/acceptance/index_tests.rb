require_relative './environment.rb'

describe 'index' do
  include Capybara::DSL
  it 'goes to signup' do
    Capybara.reset_sessions!
    visit '/'
    click_button 'Create My Site'
    page.must_have_content('Create a New Website')
  end
end