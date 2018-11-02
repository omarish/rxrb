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
  end
end
