module Rxrb
  class Rx
    class Helper
    end

    class Helper::Range
      def initialize(arg)
        @range = {}

        arg.each_pair do |key, value|
          unless ['min', 'max', 'min-ex', 'max-ex'].index(key)
            raise Rx::Exception, 'illegal argument for Rx::Helper::Range'
          end

          @range[key] = value
        end
      end

      def check(value)
        return false if !@range['min'].nil? && (value <  @range['min'])
        return false if !@range['min-ex'].nil? && (value <= @range['min-ex'])
        return false if !@range['max-ex'].nil? && (value >= @range['max-ex'])
        return false if !@range['max'].nil? && (value >  @range['max'])
        true
      end
    end
  end
end
