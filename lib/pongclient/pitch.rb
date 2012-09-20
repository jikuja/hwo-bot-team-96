# Hold info of the game board.
# For sidelines it holds the x-coordinate, for goalllines the y-coordinate.
# our_is_left is a boolean whether our goalline is the left one
class Pitch
    attr_accessor :bottom_sideline, :their_wall, :paddle_height, :paddle_width, :ball_radius, :ready
    attr_reader :top_sideline, :our_wall

    SIDELINE_OFFSET = 1.0

    #TODO: is empty initializer enough, is initalizer with two = 0 enough
    def initialize
        # adjusted into specs
        @top_sideline = 0
        @our_wall = 0
        @ready = false
    end

    def top_sideline_with_offset
        return top_sideline + SIDELINE_OFFSET
    end

    def bottom_sideline_with_offset
        return bottom_sideline - SIDELINE_OFFSET
    end

    def get_half_of_paddle_height
        return paddle_height / 2.0
    end
    
    def get_our_goalline
        return @our_wall + @paddle_width
    end

    def get_their_goalline
        return @their_wall - @paddle_width
    end

    # Returns pitch height, which is the distance from goal to another
    def get_height
        return @bottom_sideline-@top_sideline
    end

    # Returns pitch width, which is the distance from sideline to another
    def get_width
        return @their_wall-@our_wall
    end

    def get_center_y
        return get_height/2.0
    end
end
