require 'json'

class TCPObserver
    def initialize(client, player_name, request=nil)
        @tcp = client.tcp
        @player_name = player_name
        @request = request
        @ball_analyzer = client.ball_analyzer
        @our_paddle_analyzer = client.our_paddle_analyzer
        @their_paddle_analyzer = client.their_paddle_analyzer
        @pitch = client.pitch
        @sma = client.sma
    end

    # Here we read our socket, parse JSON-messages
    # and pass data from messages into Observer/Analyzer objects
    def run
        #send and save JSON message to request duel or to join into game
        if @request != nil
            @tcp.puts request_duel_message(@player_name, @request) + "\n"
            $dumplogger.info(request_duel_message(@player_name, @request))
        else
            @tcp.puts join_message(@player_name) + "\n"
            $dumplogger.info(join_message(@player_name))
        end

        while json = @tcp.gets
            #save incoming message
            $dumplogger.info(json.chomp)

            #try to parse incoming JSON message
            #if parsin failscontinue with next message
            begin
                message = JSON.parse(json)
            rescue JSON::JSONError => e
                STDERR.puts e
                next
            end

            case message['msgType']
                when 'joined'
                    $logger.info "Game visualization url #{message['data']}"
                when 'gameStarted'
                    $logger.info "... game on! Paddling against #{message['data']}"
                when 'gameIsOn'
                    $mutex.synchronize do
                        handle_gameIsOn_data message
                    end
                when 'gameIsOver'
                    #clear GameBallAnalyzer state as soon as possible
                    $mutex.synchronize do
                        @ball_analyzer.clear_coordinates
                        @their_paddle_analyzer.clear_coordinates
                        @our_paddle_analyzer.clear_coordinates
                        @sma.clear_speed
                        @ball_analyzer.number_of_hits = 0
                    end
                    $logger.info "Game over... #{message['data']} won!"
                else
                    $logger.warn "Unknown message: #{message}"
                end
        end
    end

    private #­-----------------------------------------------------------------------
    def join_message(player_name)
        %Q!{"msgType":"join","data":"#{player_name}"}!
    end

    def request_duel_message(player_name, opponent)
        %Q!{"msgType":"requestDuel","data":["#{player_name}", "#{opponent}"]}!
    end

    def handle_gameIsOn_data(message)
        if message["data"]["time"].class.ancestors.include? Numeric
            time = message["data"]["time"]
        else
            time = false
        end

        #use gameIsOn data to configure Pitch object
        flag = false
        if message["data"]["conf"]["maxHeight"].class.ancestors.include? Numeric
            @pitch.bottom_sideline = message["data"]["conf"]["maxHeight"]
        else
            flag = true
        end
        if message["data"]["conf"]["maxWidth"].class.ancestors.include? Numeric
            @pitch.their_wall = message["data"]["conf"]["maxWidth"]
        else
            flag = true
        end
        if message["data"]["conf"]["paddleHeight"].class.ancestors.include? Numeric
            @pitch.paddle_height = message["data"]["conf"]["paddleHeight"]
        else
            flag=true
        end
        if message["data"]["conf"]["paddleWidth"].class.ancestors.include? Numeric
            @pitch.paddle_width = message["data"]["conf"]["paddleWidth"]
        else
            flag = true
        end
        if message["data"]["conf"]["ballRadius"].class.ancestors.include? Numeric
            @pitch.ball_radius = message["data"]["conf"]["ballRadius"]
        else
            flag = true
        end
        if flag
            @pitch.ready = false
        else
            @pitch.ready = true
        end

        #Use  gameIsOn message to configure Paddles
        flag = false
        if time != false && (message["data"]["left"]["y"].class.ancestors.include? Numeric)
            our = XYTCoordinates.new(0, message["data"]["left"]["y"], time)
            @our_paddle_analyzer.add_coordinates(our)
            @our_paddle_analyzer.ready = true
        end
        if time != false && (message["data"]["right"]["y"].class.ancestors.include? Numeric)
            their = XYTCoordinates.new(0, message["data"]["right"]["y"], time)
            @their_paddle_analyzer.add_coordinates(their)
            @their_paddle_analyzer.ready = true
        end

        #Use gameIsOn message to configre Ball position and timestamp
        if time != false && ( message["data"]["ball"]["pos"]["x"].class.ancestors.include? Numeric) &&
            (message["data"]["ball"]["pos"]["y"].class.ancestors.include? Numeric)

            x = message["data"]["ball"]["pos"]["x"]
            y = message["data"]["ball"]["pos"]["y"]
            xyt = XYTCoordinates.new(x, y, time)
            @ball_analyzer.add_coordinates(xyt, true)
        end

        #and finally print analysis
        @ball_analyzer.print_info
        #@ball_analyzer.give_pass_coordinates(true)
    end
end
