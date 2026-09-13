# frozen_string_literal: true

require 'colorize'

module Crosspack
  # CLI message coloring (green = success, red = errors, yellow = warnings),
  # powered by the colorize gem. Colors are turned off automatically when the
  # output is not a TTY or NO_COLOR is set, so piped and logged output stays
  # clean.
  module Colors
    class << self
      attr_writer :enabled

      def enabled?
        return @enabled unless @enabled.nil?

        ENV['NO_COLOR'].nil? && ($stdout.tty? || $stderr.tty?)
      end

      def red(text)
        enabled? ? text.to_s.colorize(:red) : text
      end

      def green(text)
        enabled? ? text.to_s.colorize(:green) : text
      end

      def yellow(text)
        enabled? ? text.to_s.colorize(:yellow) : text
      end
    end
  end
end
