# The BlackBox is a component that we don't include in the source code.
# It is used for our anti-spam code, which is not public.
# If you're a spammer and reading this to try to break it, please leave us alone.
# All you're doing is hurting a site that's trying to make the internet suck
# less and prevent it from turning into an soviet-apartment-bloc social network Orwellian nightmare.
# Also, we will very quickly detect and change the black box as soon as you figure out how to break it.
# Please choose another site to go after, we implore you.

class BlackBox
  class << self
    def generate(*args)
      'derp'
    end

    def valid?(input, ip)
      input == 'derp'
    end
  end
end