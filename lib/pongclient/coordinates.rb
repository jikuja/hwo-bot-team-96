# Class that holds x and y coordinates
class XYCoordinates
    attr_accessor :x, :y

    def initialize(x, y)
        # Force floats by dividing by 1.0
        @x = x/1.0
        @y = y/1.0
    end
end

# Class that holds x and y coordinates and time coordinate as well
class XYTCoordinates < XYCoordinates
    attr_reader :t

    # The ball has coordinates x and y (int) and time t (milliseconds)
    def initialize(x, y, t)
        super(x, y)
        @t = t
    end
end
