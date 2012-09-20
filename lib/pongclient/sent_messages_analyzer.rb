class SentMessagesAnalyzer
    def initialize
        @sent_messages = Array.new
    end

    # Compares the new suggested speed to the previously sent.
    # We don't want to send a new speed if it's the same as earlier
    def is_same_speed(new_speed)
        if @sent_messages.length == 0
            return false
        end

        return new_speed == @sent_messages[-1].speed
    end

    def current_speed
        return @sent_messages[-1].speed
    end

    def log_message(speed)
        @sent_messages.push( Message.new(speed) )
        if @sent_messages.length > 42
            remove_oldest_message
        end
        puts "ai.run: speed: #{speed} sma count: #{count_messages(2)}"
    end

    def remove_oldest_message
        @sent_messages.delete_at(0)
    end

    def count_messages(ms)
        return @sent_messages.count{ |x| (Time.now-x.timestamp).abs < ms }
    end
end

# Stores data for a message that is sent to the game server
class Message
    attr_reader :speed, :timestamp

    def initialize(speed)
        @speed = speed
        @timestamp = Time.now
    end
end

