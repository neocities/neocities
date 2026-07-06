TUTORIAL_PAGE_COUNT = 10
TUTORIAL_COMPLETION_PAGE = 9

TUTORIAL_PAGE_TITLES = {
  1  => 'Make Your First Edit',
  2  => 'Tags: The Building Blocks',
  3  => 'Headings',
  4  => 'The Invisible Part of the Page',
  5  => 'Links',
  6  => 'Images',
  7  => 'Lists',
  8  => 'A Splash of Color',
  9  => 'Review And Save',
  10 => 'You Made a Website!'
}.freeze

def tutorial_page_title(page)
  TUTORIAL_PAGE_TITLES[page.to_i]
end

# The canonical state of the student's page at the *start* of each tutorial
# page, assuming they completed every previous step with the example answers.
# Used to fill the editor when there is no saved work (for example, when
# someone jumps into the middle of the tutorial), and by the Reset button.
def tutorial_starter_html(page)
  page = page.to_i

  head_lines = []
  head_lines << (page >= 5 ? '<title>My Corner of the Web</title>' : '<title>My First Website</title>')

  if page >= TUTORIAL_COMPLETION_PAGE
    head_lines << '<style>'
    head_lines << '  body {'
    head_lines << '    background-color: lightskyblue;'
    head_lines << '  }'
    head_lines << '</style>'
  end

  body_lines = []
  body_lines << '<h1>My Website</h1>' if page >= 4

  if page <= 1
    body_lines << 'Hello World!'
  elsif page == 2
    body_lines << 'Welcome to my website!'
  else
    body_lines << '<p>Welcome to my website!</p>'
    body_lines << '<p>I am learning HTML, and I built this page myself.</p>'
  end

  if page >= 6
    body_lines << ''
    body_lines << '<p>My favorite place on the web is <a href="https://neocities.org">Neocities</a>.</p>'
  end

  if page >= 7
    body_lines << ''
    body_lines << '<img src="/neocities.png" alt="The Neocities cat">'
  end

  if page >= 8
    body_lines << ''
    body_lines << '<h2>Things I Like</h2>'
    body_lines << '<ul>'
    body_lines << '  <li>Making websites</li>'
    body_lines << '  <li>Cats</li>'
    body_lines << '</ul>'
  end

  head = head_lines.map { |line| "    #{line}" }.join "\n"
  body = body_lines.map { |line| line.empty? ? '' : "    #{line}" }.join "\n"

  "<!DOCTYPE html>\n<html>\n  <head>\n#{head}\n  </head>\n  <body>\n#{body}\n  </body>\n</html>"
end

def default_tutorial_html
  tutorial_starter_html 1
end

get '/tutorials' do
  @description = 'Start web development tutorials on Neocities.'
  erb :'tutorials'
end

get '/tutorial/?' do
  require_login
  erb :'tutorial/index'
end

get '/tutorial/:section/?' do
  require_login
  not_found unless %w{html}.include?(params[:section])
  redirect "/tutorial/#{params[:section]}/1"
end

get '/tutorial/:section/:page/?' do
  require_login
  not_found unless %w{html}.include?(params[:section])

  @page = params[:page].to_i
  not_found unless params[:page] == @page.to_s && @page.between?(1, TUTORIAL_PAGE_COUNT)

  @section = params[:section]
  @title = "#{@section.upcase} Tutorial - #{@page}/#{TUTORIAL_PAGE_COUNT}"

  if @page == TUTORIAL_COMPLETION_PAGE
    redirect "/tutorial/#{@section}/#{TUTORIAL_COMPLETION_PAGE - 1}" unless csrf_safe?

    if current_site.tutorial_required
      current_site.tutorial_required = false
      current_site.save_changes validate: false
    end
  end

  erb "tutorial/layout".to_sym
end
