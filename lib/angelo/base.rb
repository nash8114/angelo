module Angelo

  class Base
    include ParamsParser
    include Celluloid::Logger

    extend Forwardable
    def_delegators :@responder, :content_type, :headers, :request

    attr_accessor :responder

    class << self

      attr_accessor :app_file

      def inherited subclass
        subclass.app_file = caller(1).map {|l| l.split(/:(?=|in )/, 3)[0,1]}.flatten[0]

        def subclass.root
          @root ||= File.expand_path '..', app_file
          @root
        end

        def subclass.view_dir
          v = self.class_variable_get(:@@views) rescue 'views'
          File.join root, v
        end

      end

      def compile! name, &block
        define_method name, &block
        method = instance_method name
        remove_method name
        method
      end

      def routes
        @routes ||= {}
        ROUTABLE.each do |m|
          @routes[m] ||= {}
        end
        @routes
      end

      def before opts = {}, &block
        define_method :before, &block
      end

      def after opts = {}, &block
        define_method :after, &block
      end

      HTTPABLE.each do |m|
        define_method m do |path, &block|
          routes[m][path] = Responder.new &block
        end
      end

      def socket path, &block
        routes[:socket][path] = WebsocketResponder.new &block
      end

      def websockets
        @websockets ||= WebsocketsArray.new
        @websockets.reject! &:closed?
        @websockets
      end

      def content_type type
        Responder.content_type type
      end

      def run host = DEFAULT_ADDR, port = DEFAULT_PORT
        @server = Angelo::Server.new self, host, port
        trap "INT" do
          @server.terminate if @server and @server.alive?
          exit
        end
        sleep
      end

    end

    def params
      @params ||= case request.method
                  when GET;  parse_query_string
                  when POST; parse_post_body
                  when PUT;  parse_post_body
                  end
      @params
    end

    def websockets; self.class.websockets; end

    class WebsocketsArray < Array

      def each &block
        super do |ws|
          begin
            yield ws
          rescue Reel::SocketError => rse
            warn "#{rse.class} - #{rse.message}"
            delete ws
          end
        end
      end

      def [] context
        @@websockets ||= {}
        @@websockets[context] ||= self.class.new
      end

    end

  end

end
