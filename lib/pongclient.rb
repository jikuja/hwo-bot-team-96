require 'socket'
require 'logger'

require 'pongclient/game_ball_analyzer.rb'
require 'pongclient/pitch.rb'
require 'pongclient/paddle.rb'
require 'pongclient/sent_messages_analyzer.rb'
require 'pongclient/coordinates.rb'
require 'pongclient/tcp_observer.rb'

class PongClient
    attr_accessor :tcp, :pitch, :our_paddle_analyzer, :their_paddle_analyzer, :ball_analyzer, :sma, :t1, :t2
    def initialize(player_name, server_host, server_port, dump_logger_file="client-dump.log", logger_level=3, ai="pongclient/ai.rb", request=nil)
        #setup loggers
        #normal logger for stdout
        #TODO: formatting
        $logger = Logger.new(STDOUT)
        $logger.level = logger_level

        #dumplogger for file logging
        #log all client and sserver JSON messages here
        $dumplogger = Logger.new(dump_logger_file, 10, 32*(2**20))
        $dumplogger.level = Logger::DEBUG

        #Use simple format for dump log: easier to parse later
        $dumplogger.formatter = proc do |severity, datetime, progname, msg|
            (datetime.to_f*1000).to_s + " " + msg.to_s + "\n"
        end

        #try to load supplied AI file
        # TODO: make better!
        #       do we needd to supply some kind of ai in lib/?
        tried_from_lib = false
        tried_from_dot = false
        begin
            require ai
        rescue LoadError => e
            if tried_from_lib == false && ! ai[/pongclient\//]
                oldai = ai
                ai = "pongclient/" + ai
                tried_from_lib = true
                retry
            else
                ai = "./" + oldai
                tried_from_dot = true
                retry
            end
            puts e
            exit 0
        end

        #We need to open TCPsocket here because AI needs to write into it
        @tcp = TCPSocket.open(server_host, server_port)
        #disable Nagle's algorithm
        @tcp.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

        #create class instantiations which we are going to use
        @pitch = Pitch.new

        # TODO: refactor: two class, initilizet, setters
        @our_paddle_analyzer = Paddle.new(self)
        @their_paddle_analyzer = Paddle.new(self)

        # TODO: clean and refactor class code
        @ball_analyzer = GameBallAnalyzer.new(self)
        @sma = SentMessagesAnalyzer.new

        @tcp_observer = TCPObserver.new(self, player_name, request)
        @ai = AI.new(self)

        #start thread for TCP observer and AI loops
        @t1 = Thread.new{@tcp_observer.run}
        @t2 = Thread.new{@ai.run}

        #Stop execution of proram if there is unhandled exception inour threads
        @t1.abort_on_exception = true
        @t2.abort_on_exception = true

        #Wait threads to stop.
        @t1.join
        @t2.join
    end
end
