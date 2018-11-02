# frozen_string_literal: true

module Rxrb
  class Rx
    def self.schema(schema)
      Rx.new(load_core: true).make_schema(schema)
    end

    def initialize(opt = {})
      @type_registry = {}
      @prefix = {
        ''      => 'tag:codesimply.com,2008:rx/core/',
        '.meta' => 'tag:codesimply.com,2008:rx/meta/'
      }

      Type::Core.core_types.each { |t| register_type(t) } if opt[:load_core]
    end

    def register_type(type)
      uri = type.uri

      if @type_registry.key?(uri)
        raise Rx::Exception, "attempted to register already-known type #{uri}"
      end

      @type_registry[uri] = type
    end

    def learn_type(uri, schema)
      if @type_registry.key?(uri)
        raise Rx::Exception, "attempted to learn type for already-registered uri #{uri}"
      end

      # make sure schema is valid
      # should this be in a begin/rescue?
      make_schema(schema)

      @type_registry[uri] = { 'schema' => schema }
    end

    def expand_uri(name)
      return name if /\A\w+:/.match?(name)

      match = name.match(/\A\/(.*?)\/(.+)\z/)
      unless match
        raise Rx::Exception, "couldn't understand Rx type name: #{name}"
      end

      unless @prefix.key?(match[1])
        raise Rx::Exception, "unknown prefix '#{match[1]}' in name 'name'"
      end

      @prefix[ match[1] ] + match[2]
    end

    def add_prefix(name, base)
      if @prefix.key?(name)
        throw Rx::Exception.new("the prefix '#{name}' is already registered")
      end

      @prefix[name] = base
    end

    def make_schema(schema)
      schema = { 'type' => schema } if schema.instance_of?(String)

      unless schema.instance_of?(Hash) && schema['type']
        raise Rx::Exception, 'invalid type'
      end

      uri = expand_uri(schema['type'])

      raise Rx::Exception, 'unknown type' unless @type_registry.key?(uri)

      type_class = @type_registry[uri]

      if type_class.instance_of?(Hash)
        if schema.keys != ['type']
          raise Rx::Exception, 'composed type does not take check arguments'
        end
        return make_schema(type_class['schema'])
      else
        return type_class.new(schema, self)
      end
    end

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

    class Exception < StandardError
    end

    class ValidationError < StandardError
      attr_accessor :path

      def initialize(message, path)
        @message = message
        @path = path
      end

      def path
        @path ||= ''
      end

      def message
        "#{@message} (#{@path})"
      end

      def inspect
        "#{@message} (#{@path})"
      end

      def to_s
        inspect
      end
    end

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

      class Type::Core < Type
        class << self
          def uri
            'tag:codesimply.com,2008:rx/core/' + subname
          end
        end

        def check(value)
          check!(value)
          true
        rescue ValidationError
          false
        end

        class All < Type::Core
          @@allowed_param = { 'of' => true, 'type' => true }
          def allowed_param?(p)
            @@allowed_param[p]
          end

          def initialize(param, rx)
            super

            unless param.key?('of')
              raise Rx::Exception, "no 'of' parameter provided for #{uri}"
            end

            if param['of'].empty?
              raise Rx::Exception, "no schemata provided for 'of' in #{uri}"
            end

            @alts = []
            param['of'].each { |alt| @alts.push(rx.make_schema(alt)) }
          end

          class << self
            def subname
              'all'
            end
          end

          def check!(value)
            @alts.each do |alt|
              alt.check!(value)
            rescue ValidationError => e
              e.path = '/all' + e.path
              raise e
            end
            true
          end
        end

        class Any < Type::Core
          @@allowed_param = { 'of' => true, 'type' => true }
          def allowed_param?(p)
            @@allowed_param[p]
          end

          def initialize(param, rx)
            super

            if param['of']
              if param['of'].empty?
                raise Rx::Exception, "no alternatives provided for 'of' in #{uri}"
              end

              @alts = []
              param['of'].each { |alt| @alts.push(rx.make_schema(alt)) }
            end
          end

          class << self
            def subname
              'any'
            end
          end

          def check!(value)
            return true unless @alts

            @alts.each do |alt|
              return true if alt.check!(value)
            rescue ValidationError
            end

            raise ValidationError.new('expected one to match', '/any')
          end
        end

        class Arr < Type::Core
          class << self
            def subname
              'arr'
            end
          end

          @@allowed_param = { 'contents' => true, 'length' => true, 'type' => true }
          def allowed_param?(p)
            @@allowed_param[p]
          end

          def initialize(param, rx)
            super

            unless param['contents']
              raise Rx::Exception, "no contents schema given for #{uri}"
            end

            @contents_schema = rx.make_schema(param['contents'])

            if param['length']
              @length_range = Rx::Helper::Range.new(param['length'])
            end
          end

          def check!(value)
            unless value.instance_of?(Array)
              raise ValidationError.new("expected array got #{value.class}", '/arr')
            end

            if @length_range
              unless @length_range.check(value.length)
                raise ValidationError.new("expected array with #{@length_range} elements, got #{value.length}", '/arr')
              end
            end

            if @contents_schema
              value.each do |v|
                @contents_schema.check!(v)
              rescue ValidationError => e
                e.path = '/arr' + e.path
                raise e
              end
            end

            true
          end
        end

        class Bool < Type::Core
          class << self
            def subname
              'bool'
            end
          end

          include Type::NoParams

          def check!(value)
            unless value.instance_of?(TrueClass) || value.instance_of?(FalseClass)
              raise ValidationError.new("expected bool got #{value.inspect}", '/bool')
            end
            true
          end
        end

        class Fail < Type::Core
          class << self
            def subname
              'fail'
            end
          end

          include Type::NoParams

          def check(_value)
            false
          end

          def check!(_value)
            raise ValidationError.new('explicit fail', '/fail')
          end
        end

        #
        # Added by dan - 81030
        class Date < Type::Core
          class << self; def subname
                          'date'
                          end; end

          include Type::NoParams

          def check!(value)
            unless value.instance_of?(::Date)
              raise ValidationError("expected Date got #{value.inspect}", '/date')
            end
            true
          end
        end

        class Def < Type::Core
          class << self
            def subname
              'def'
            end
          end

          include Type::NoParams
          def check!(value)
            raise ValidationError.new('def failed', '/def') if value.nil?
          end
        end

        class Map < Type::Core
          class << self; def subname
                          'map'
                          end; end
          @@allowed_param = { 'values' => true, 'type' => true }
          def allowed_param?(p)
            @@allowed_param[p]
          end

          def initialize(param, rx)
            super

            unless param['values']
              raise Rx::Exception, "no values schema given for #{uri}"
            end

            @value_schema = rx.make_schema(param['values'])
          end

          def check!(value)
            unless value.instance_of?(Hash) || (value.class.to_s == 'HashWithIndifferentAccess')
              raise ValidationError.new("expected map got #{value.inspect}", '/map')
            end

            if @value_schema
              value.each_value do |v|
                @value_schema.check!(v)
              rescue ValidationError => e
                e.path = '/map' + e.path
                raise e
              end
            end

            true
          end
        end

        class Nil < Type::Core
          class << self; def subname
                          'nil'
                          end; end
          include Type::NoParams
          def check!(value)
            raise ValidationError.new("expected nil got #{value.inspect}", '/nil') unless value.nil?
            true
          end
        end

        class Num < Type::Core
          class << self; def subname
                          'num'
                          end; end
          @@allowed_param = { 'range' => true, 'type' => true, 'value' => true }
          def allowed_param?(p)
            @@allowed_param[p]
          end

          def initialize(param, rx)
            super

            if param.key?('value')
              unless param['value'].is_a?(Numeric)
                raise Rx::Exception, "invalid value parameter for #{uri}"
              end

              @value = param['value']
            end

            @value_range = Rx::Helper::Range.new(param['range']) if param['range']
          end

          def check!(value)
            unless value.is_a?(Numeric)
              raise ValidationError.new("expected Numeric got #{value.inspect}", "/#{self.class.subname}")
            end
            if @value_range && !@value_range.check(value)
              raise ValidationError.new("expected Numeric in range #{@value_range} got #{value.inspect}", "/#{self.class.subname}")
            end
            if @value && (value != @value)
              raise ValidationError.new("expected Numeric to equal #{@value} got #{value.inspect}", "/#{self.class.subname}")
            end
            true
          end
        end

        class Int < Type::Core::Num
          class << self; def subname
                          'int'
                          end; end

          def initialize(param, rx)
            super

            if @value && (@value % 1 != 0)
              raise Rx::Exception, "invalid value parameter for #{uri}"
            end
          end

          def check!(value)
            super
            unless value % 1 == 0
              raise ValidationError.new("expected Integer got #{value.inspect}", '/int')
            end
            true
          end
        end

        class One < Type::Core
          class << self; def subname
                          'one'
                          end; end
          include Type::NoParams

          def check!(value)
            unless [Numeric, String, TrueClass, FalseClass].any? { |cls| value.is_a?(cls) }
              raise ValidationError.new("expected One got #{value.inspect}", '/one')
            end
          end
        end

        class Rec < Type::Core
          class << self; def subname
                          'rec'
                          end; end
          @@allowed_param = {
            'type' => true,
            'rest' => true,
            'required' => true,
            'optional' => true
          }

          def allowed_param?(p)
            @@allowed_param[p]
          end

          def initialize(param, rx)
            super

            @field = {}

            @rest_schema = rx.make_schema(param['rest']) if param['rest']

            %w[optional required].each do |type|
              next unless param[type]
              param[type].keys.each do |field|
                if @field[field]
                  raise Rx::Exception, "#{field} in both required and optional"
                end

                @field[field] = {
                  required: (type == 'required'),
                  schema: rx.make_schema(param[type][field])
                }
              end
            end
          end

          def check!(value)
            unless value.instance_of?(Hash) || (value.class.to_s == 'HashWithIndifferentAccess')
              raise ValidationError.new("expected Hash got #{value.class}", '/rec')
            end

            rest = []

            value.each do |field, field_value|
              unless @field[field]
                rest.push(field)
                next
              end

              begin
                @field[field][:schema].check!(field_value)
              rescue ValidationError => e
                e.path = "/rec:'#{field}'"
                raise e
              end
            end

            @field.select { |k, _v| @field[k][:required] }.each do |pair|
              unless value.key?(pair[0])
                raise ValidationError.new("expected Hash to have key: '#{pair[0]}', only had #{value.keys.inspect}", '/rec')
              end
            end

            unless rest.empty?
              unless @rest_schema
                raise ValidationError.new("Hash had extra keys: #{rest.inspect}", '/rec')
              end
              rest_hash = {}
              rest.each { |field| rest_hash[field] = value[field] }
              begin
                @rest_schema.check!(rest_hash)
              rescue ValidationError => e
                e.path = '/rec'
                raise e
              end
            end

            true
          end
        end

        class Seq < Type::Core
          class << self; def subname
                          'seq'
                          end; end
          @@allowed_param = { 'tail' => true, 'contents' => true, 'type' => true }
          def allowed_param?(p)
            @@allowed_param[p]
          end

          def initialize(param, rx)
            super

            unless param['contents']&.is_a?(Array)
              raise Rx::Exception, "missing or invalid contents for #{uri}"
            end

            @content_schemata = param['contents'].map { |s| rx.make_schema(s) }

            @tail_schema = rx.make_schema(param['tail']) if param['tail']
          end

          def check!(value)
            unless value.instance_of?(Array)
              raise ValidationError.new("expected Array got #{value.inspect}", '/seq')
            end
            if value.length < @content_schemata.length
              raise ValidationError.new("expected Array to have at least #{@content_schemata.length} elements, had #{value.length}", '/seq')
            end
            @content_schemata.each_index do |i|
              @content_schemata[i].check!(value[i])
            rescue ValidationError => e
              e.path = '/seq' + e.path
              raise e
            end

            if value.length > @content_schemata.length
              unless @tail_schema
                raise ValidationError.new('expected tail_schema', '/seq')
              end
              begin
                @tail_schema.check!(value[
                                          @content_schemata.length,
                                          value.length - @content_schemata.length
                                        ])
              rescue ValidationError => e
                e.path = '/seq' + e.path
                raise e
              end
            end

            true
          end
        end

        class Str < Type::Core
          class << self; def subname
                          'str'
                          end; end
          @@allowed_param = {
            'type' => true,
            'value' => true,
            'length' => true,
            'regex' => true
          }

          def allowed_param?(p)
            @@allowed_param[p]
          end

          def initialize(param, rx)
            super

            if param['length']
              @length_range = Rx::Helper::Range.new(param['length'])
            end

            if param.key?('value')
              unless param['value'].instance_of?(String)
                raise Rx::Exception, "invalid value parameter for #{uri}"
              end

              @value = param['value']
            end

            if param.key?('regex')
              # boom do it here
            end
          end

          def check!(value)
            unless value.instance_of?(String)
              raise ValidationError.new("expected String got #{value.inspect}", '/str')
            end

            if @length_range
              unless @length_range.check(value.length)
                raise ValidationError.new("expected string with #{@length_range} characters, got #{value.length}", '/str')
              end
            end

            if @value && (value != @value)
              raise ValidationError.new("expected #{@value.inspect} got #{value.inspect}", '/str')
            end
            true
          end
        end

        #
        # Added by dan - 81106
        class Time < Type::Core
          class << self; def subname
                          'time'
                          end; end

          include Type::NoParams

          def check!(value)
            unless value.instance_of?(::Time)
              raise ValidationError.new("expected Time got #{value.inspect}", '/time')
            end
            true
          end
        end

        class << self
          def core_types
            [
              Type::Core::All,
              Type::Core::Any,
              Type::Core::Arr,
              Type::Core::Bool,
              Type::Core::Date,
              Type::Core::Def,
              Type::Core::Fail,
              Type::Core::Int,
              Type::Core::Map,
              Type::Core::Nil,
              Type::Core::Num,
              Type::Core::One,
              Type::Core::Rec,
              Type::Core::Seq,
              Type::Core::Str,
              Type::Core::Time
            ]
          end
        end
      end
    end
  end
end
