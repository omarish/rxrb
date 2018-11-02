module Rxrb
  class Rx
    class Type
      def initialize(param, _rx)
        assert_valid_params(param)
      end

      def uri
        self.class.uri
      end

      def assert_valid_params(param)
        param.each_key do |k|
          unless allowed_param?(k)
            raise Rx::Exception, "unknown parameter #{k} for #{uri}"
          end
        end
      end

      module NoParams
        def initialize(param, _rx)
          return if param.keys.empty?
          return if param.keys == ['type']

          raise Rx::Exception, 'this type is not parameterized'
        end
      end
    end
  end
end
