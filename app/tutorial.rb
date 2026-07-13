TUTORIAL_PAGE_COUNT = 10
TUTORIAL_COMPLETION_PAGE = 9

TUTORIAL_SECTIONS = %w{html html2 css js}.freeze

TUTORIAL_SECTION_TITLES = {
  'html'  => 'HTML',
  'html2' => 'More HTML',
  'css'   => 'CSS',
  'js'    => 'JavaScript'
}.freeze

TUTORIAL_PAGE_TITLES = {
  'html' => {
    1  => 'Make Your First Edit',
    2  => 'Tags and Elements',
    3  => 'Headings',
    4  => 'The Invisible Part of the Page',
    5  => 'Links',
    6  => 'Images',
    7  => 'Lists',
    8  => 'A Splash of Color',
    9  => 'Review And Save',
    10 => 'You Made a Website!'
  },
  'html2' => {
    1  => 'Bold, Italic, and Friends',
    2  => 'Line Breaks and Poetry',
    3  => 'A Quote to Live By',
    4  => 'Hearts, Stars, and Symbols',
    5  => 'Invisible Ink: Comments',
    6  => 'Click to Reveal a Secret',
    7  => 'Jump Links',
    8  => 'Divs: Boxes with Names',
    9  => 'Review Your Page',
    10 => 'Your Page Leveled Up!'
  },
  'css' => {
    1  => 'Your First Style Rules',
    2  => 'Millions of Colors',
    3  => 'Choosing Your Fonts',
    4  => 'The Class Selector',
    5  => 'Boxes, Borders, and Corners',
    6  => 'Centering Your Page',
    7  => 'Links with Personality',
    8  => 'Painting the Sky',
    9  => 'Review Your Page',
    10 => 'You Have Style!'
  },
  'js' => {
    1  => 'Your First Script',
    2  => 'Variables',
    3  => 'Functions',
    4  => 'Buttons and Clicks',
    5  => 'Day and Night',
    6  => 'Random Surprises',
    7  => 'The Cat Needs Petting',
    8  => 'What Day Is It?',
    9  => 'Review Your Page',
    10 => "It's Alive!"
  }
}.freeze

def tutorial_section_title(section)
  TUTORIAL_SECTION_TITLES[section]
end

def tutorial_page_title(section, page)
  TUTORIAL_PAGE_TITLES[section][page.to_i]
end

def tutorial_starter_html(section, _page = nil)
  File.read(File.join(DIR_ROOT, 'views', 'tutorial', section, '1.starter.html')).chomp
end

def default_tutorial_html
  tutorial_starter_html 'html'
end

get '/tutorials' do
  @title = 'Learn How to Make Websites'
  @description = 'Learn how to make websites, starting from zero. Free interactive HTML, CSS, and JavaScript tutorials for building your own corner of the web.'
  erb :'tutorials'
end

get '/tutorial/?' do
  if current_site && current_site.tutorial_required
    erb :'tutorial/welcome'
  else
    redirect '/tutorials'
  end
end

get '/tutorial/:section/?' do
  require_login
  not_found unless TUTORIAL_SECTIONS.include?(params[:section])
  redirect "/tutorial/#{params[:section]}/1"
end

get '/tutorial/:section/:page/?' do
  require_login
  @section = params[:section]
  not_found unless TUTORIAL_SECTIONS.include?(@section)

  @page = params[:page].to_i
  not_found unless params[:page] == @page.to_s && @page.between?(1, TUTORIAL_PAGE_COUNT)

  @title = "#{tutorial_section_title(@section)} Tutorial - #{@page}/#{TUTORIAL_PAGE_COUNT}"

  walk = (session[:tutorial_walk] || {})[@section] || 1

  if @page > walk && !(@page == TUTORIAL_PAGE_COUNT && walk >= TUTORIAL_COMPLETION_PAGE)
    redirect "/tutorial/#{@section}/#{walk}"
  end

  if @page == TUTORIAL_COMPLETION_PAGE && current_site.tutorial_required
    current_site.tutorial_required = false
    current_site.save_changes validate: false
  end

  erb "tutorial/layout".to_sym
end

post '/tutorial/:section/:page/?' do
  require_login
  @section = params[:section]
  not_found unless TUTORIAL_SECTIONS.include?(@section)

  @page = params[:page].to_i
  not_found unless params[:page] == @page.to_s && @page.between?(1, TUTORIAL_PAGE_COUNT - 1)

  walks = session[:tutorial_walk] || {}
  walk = walks[@section] || 1

  redirect "/tutorial/#{@section}/#{walk}" if @page > walk

  session[:tutorial_walk] = walks.merge(@section => @page + 1) if @page == walk

  redirect "/tutorial/#{@section}/#{@page + 1}"
end
