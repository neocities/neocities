class Sinatra::Base
  alias_method :render_original, :render
  def render(engine, data, options = {}, locals = {}, &block)
    options.merge!(pretty: self.class.development?) if engine == :slim && options[:pretty].nil?
    render_original engine, data, options, locals, &block
  end
end