class Paddle
    attr_accessor :width, :height, :ready
    
    # The incoming coordinate is from top left corner.
    # The saved y-coordinate is CENTERED TO THE PADDLE
    def initialize(client)
        @pitch = client.pitch
        @coordinates = Array.new
        @ready = false
    end
    
    public #------------------------------------------------------------

    # Public
    def add_coordinates(coords)
        coords.y = fix_y(coords.y)
        @coordinates.push(coords)
    end

    # Public
    def get_y
        return @coordinates[-1].y
    end
    
    # Public
    # This is only used for opponent paddle analyzing. Make a new class?
    def is_moving
        return (@coordinates[-1].y - @coordinates[-2].y).abs > 0.0000001
    end
    
    private #-------------------------------------------------------------------------
    # Private
    # The parameter coordinate is for the upper side of the paddle
    # Returns the corresponding parameter for center of paddle
    def fix_y(y_coord)
        return y_coord+@pitch.paddle_height/2.0
    end

    # Private
    # ?? This should probably be a public method and called every once in a while
    # just because it stores data that is not really used.
    def clear_coordinates
        @coordinates.clear    
    end
    
end

