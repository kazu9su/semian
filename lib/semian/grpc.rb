require 'semian/adapter'
require 'grpc'

module GRPC
  GRPC::Unavailable.include(::Semian::AdapterError)
  GRPC::Unknown.include(::Semian::AdapterError)
  GRPC::ResourceExhausted.include(::Semian::AdapterError)

  class SemianError < GRPC::Unavailable
    attr_reader :details

    def initialize(semian_identifier, *args)
      super(*args)
      @details = message
      @semian_identifier = semian_identifier
    end
  end

  ResourceBusyError = Class.new(SemianError)
  CircuitOpenError = Class.new(SemianError)
end

module Semian
  module GRPC
    attr_reader :raw_semian_options
    include Semian::Adapter

    ResourceBusyError = ::GRPC::ResourceBusyError
    CircuitOpenError = ::GRPC::CircuitOpenError

    class SemianConfigurationChangedError < RuntimeError
      def initialize(msg = "Cannot re-initialize semian_configuration")
        super
      end
    end

    class << self
      attr_accessor :exceptions
      attr_reader :semian_configuration

      def semian_configuration=(configuration)
        raise Semian::GRPC::SemianConfigurationChangedError unless @semian_configuration.nil?
        @semian_configuration = configuration
      end

      def retrieve_semian_configuration(host)
        @semian_configuration.call(host) if @semian_configuration.respond_to?(:call)
      end
    end

    def raw_semian_options
      @raw_semian_options ||= begin
        # If the host is empty, it's possible that the adapter was initialized
        # with the channel. Therefore, we look into the channel to find the host
        if @host.empty?
          host = @ch.target
        else
          host = @host
        end
        @raw_semian_options = Semian::GRPC.retrieve_semian_configuration(host)
        @raw_semian_options = @raw_semian_options.dup unless @raw_semian_options.nil?
      end
    end

    def semian_identifier
      @semian_identifier ||= raw_semian_options[:name]
    end

    def resource_exceptions
      [
        ::GRPC::DeadlineExceeded,
        ::GRPC::ResourceExhausted,
        ::GRPC::Unavailable,
        ::GRPC::Unknown,
      ]
    end

    def request_response(*args)
      acquire_semian_resource(adapter: :grpc, scope: :request_response) { super(*args) }
    end

    def client_streamer(*args)
      acquire_semian_resource(adapter: :grpc, scope: :client_streamer) { super(*args) }
    end

    def server_streamer(*args)
      acquire_semian_resource(adapter: :grpc, scope: :server_streamer) { super(*args) }
    end

    def bidi_streamer(*args)
      acquire_semian_resource(adapter: :grpc, scope: :bidi_streamer) { super(*args) }
    end
  end
end

::GRPC::ClientStub.prepend(Semian::GRPC)
