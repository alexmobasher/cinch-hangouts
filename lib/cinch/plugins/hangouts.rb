# -*- coding: utf-8 -*-
require 'cinch'
require 'cinch-storage'
require 'cinch/toolbox'
require 'time-lord'

module Cinch::Plugins
  class Hangouts
    include Cinch::Plugin
    @@hangout_filename = ''
    @@subscription_filename = ''

    attr_accessor :storage

    self.help = "Use .hangouts to see the info for any recent hangouts. You can also use .hangouts subscribe to sign up for notifications."

    match /hangouts\z/,           method: :list_hangouts
    match /hangouts subscribe/,   method: :subscribe
    match /hangouts unsubscribe/, method: :unsubscribe

    listen_to :channel

    # This is the regex that captures hangout links in the following format:
    #   https://plus.google.com/hangouts/_/fbae432b70a47bdf7786e53a16f364895c09d9f8
    #
    # The regex will need to be updated if the url scheme changes in the future.
    HANGOUTS_REGEX = /plus\.google\.com\/hangouts\/_\/([a-f0-9]{40})/

    def initialize(*args)
      super
      @@hangout_filename = config[:hangout_filename]           || 'yaml/hangouts.yml'
      @@subscription_filename = config[:subscription_filename] || 'yaml/hangout_subscriptions.yml'

      @expire_period     = config[:expire_period] || 120
      @response_type     = config[:response_type] || :notice
    end

    def listen(m)
      if hangout_id = m.message[HANGOUTS_REGEX, 1]
        debug "#{hangout_id}"
        if hangout = Hangout.find_by_id(hangout_id)
          # If it's an old hangout capture a new expiration time
          hangout.time = Time.now
          hangout.save
        else
          hangout = Hangout.new(m.user.nick, hangout_id, Time.now)
          hangout.save
          Subscription.notify(hangout_id, @bot)
        end
      end
    end

    def subscribe(m)
      nick = m.user.nick
      if Subscription.for_user(nick)
        msg = "You are already subscribed. "
      else
        sub = Subscription.new(nick)
        sub.save
        msg = "You are now subscribed. I will let you know when a hangout is linked. "
      end
      m.user.notice msg + "To unsubscribe use `.hangouts unsubscribe`."
    end

    def unsubscribe(m)
      nick = m.user.nick
      if Subscription.for_user(nick)
        Subscription.for_user(nick).delete
        msg = "You are now unsubscribed, and will no longer receive a messages. "
      else
        msg = "You are not subscribed. "
      end
      m.user.notice msg + "To subscribe use `.hangouts subscribe`."
    end

    def list_hangouts(m)
      Hangout.delete_expired(@expire_period)
      hangouts = Hangout.sorted

      if hangouts.empty?
        m.user.notice "No hangouts have been linked recently!"
      else
        m.user.notice "These hangouts have been linked in the last #{@expire_period} minutes. " +
                   "They may or may not still be going."
        hangouts.each do |hangout|
          m.user.notice "#{hangout.nick} started a hangout at #{Hangout.url(hangout.id)} " +
                     "it was last linked #{hangout.time.ago.to_words}"
        end
      end
    end

    def respond(m, message)
      case @response_type
      when :notice
        m.user.notice message
      when :pm
        m.user.send message
      end
    end
  end
end