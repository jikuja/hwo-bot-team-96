class GameBallAnalyzer
    # Public
    SIDELINE_HIT_OFFSET = 1.0

    def initialize(client)
        client = client
        @pitch = client.pitch

        # Contains the current ball coordinates
        # Cleared after hits to sidelines, goallines or paddles
        @coordinates = Array.new
        
        # From the ball's current location, how many times it will hit a sideline
        # before reaching our goal-line
        @future_sideline_hits = 0

        # When we know it, it will be a boolean.
        # Up is defined as human up, where y=0
        @ball_will_come_from_up = 0
    end

    def clear_coordinates
        @coordinates.clear
        @ball_will_come_from_up = 0
    end

    def ball_will_come_from_up
        return @ball_will_come_from_up
    end

    # Public
    def add_coordinates(bc, print=false)
        if hit_detected(bc, print)
            clear_coordinates
        end
        @coordinates.push(bc)
    end

    # Public
    def give_pass_coordinates(print=false)
        if @coordinates.length < 2
            puts "give_pass_coordinates: Ei tarpeeksi dataa" if print
            return false
        end

        if ! is_going_towards_our_goalline
            puts "give_pass_coordinates: Ball is going the other way" if print
            return false
        end

        if get_x < @pitch.get_our_goalline
            puts "give_pass_coordinates: Damn, the ball has passed our goalline" +
                 "(#{get_x}, #{get_y} #{get_dxdy}" if print
            #return false # as it's never too late to try
        end

        x_start = get_x
        y_start = get_y
        dx = get_dx
        dy = get_dy
        sideline_hits = 0

        # Recursive loop to get the last sideline hit before hitting our goalline
        begin
            sideline_coords = calculate_sideline_hit(x_start, y_start, dx, dy, print)
            if sideline_coords != false
                x_start = sideline_coords.x
                y_start = sideline_coords.y
                dy *= -1.0
                sideline_hits += 1
            end
        end while sideline_coords != false

        @future_sideline_hits = sideline_hits
        @ball_will_come_from_up = y_start < 10
        
        hit_coords = calculate_our_goalline_pass(x_start, y_start, dx, dy, print)
        return hit_coords
    end

    # Public
    # From the ball's current location, how many times it will hit a sideline before
    def get_future_sideline_hits
        return @future_sideline_hits
    end
    
    # Public
    # Returns boolean if the ball is currently going towards our goal-line
    def is_going_towards_our_goalline
        if @coordinates.length < 2
            return false
        end
        return get_dx < 0
    end

    # Public?
    def print_info
        if @coordinates.length == 1
            printf("Current x: %6.2f, y: %6.2f\n", get_x, get_y)
        elsif @coordinates.length > 1
            printf("Current x: %6.2f, y: %6.2f| dx: %8.3f, dy %8.3f| dx/dy: %8.3f\n", get_x, get_y, get_dx, get_dy, get_dx/get_dy)
        end
    end

    # Public
    def give_pass_coordinates2
        if @coordinates.length < 2 || ! is_going_towards_our_goalline
            return
        end
        foo = calculate_sideline_hit(get_x, get_y, -1.0*get_dx, -1.0*get_dy, false)
        if foo
            puts "Reversed Sideline hit was at (#{foo.x}, #{foo.y})"
        end
    end

    # Public
    def is_enough_coordinates
        return @coordinates.length >= 2
    end

    # Public?
    def get_dxdy
        return get_dx/get_dy
    end

    # Public?
    # Returns the ball's latest x-coordinate
    def get_x
        return @coordinates[-1].x
    end

    # Public?
    # Returns the ball's latest y-coordinate
    def get_y
        return @coordinates[-1].y
    end

    # Public?
    def get_dx
        # x1 is before x2 in time
        x_1 = @coordinates[0].x
        x_2 = @coordinates[-1].x
        return x_2-x_1
    end

    # Public?
    def get_dy
        y_1 = @coordinates[0].y
        y_2 = @coordinates[-1].y
        return y_2-y_1
    end

    # Public?
    def get_dt
        t_1 = @coordinates[0].t
        t_2 = @coordinates[-1].t
        return t_2-t_1
    end

    private # --------------------------------------------------------------------

    def calculate_sideline_hit(x_start, y_start, dx, dy, print)
        if dy < 0
            y_hit = @pitch.top_sideline_with_offset + @pitch.ball_radius
        else
            y_hit = @pitch.bottom_sideline_with_offset - @pitch.ball_radius
        end

        # The distance to travel in y before hit
        y_distance = ( y_hit - y_start ).abs
        dx_dy = (dx/dy).abs

        # x_hit is the extrapolated value after travelling the x_distance
        x_hit =  x_start - dx_dy * y_distance

        if x_hit < @pitch.get_our_goalline + @pitch.ball_radius
            return false
        else
            puts "Sideline hit at (#{x_hit}, #{y_hit})" if print
            return XYCoordinates.new(x_hit, y_hit)
        end
    end

    def calculate_our_goalline_pass(x_start, y_start, dx, dy, print)
        x_hit = @pitch.get_our_goalline

        # The distance to travel in x before hit
        x_distance = ( x_hit - x_start ).abs
        dx_dy = (dx/dy).abs

        # y_hit is the extrapolated value after travelling the x_distance
        if (dy > 0)
            y_hit = y_start + (1.0/dx_dy) * x_distance
        elsif
            y_hit = y_start - (1.0/dx_dy) * x_distance
        end

        puts "Will hit our goalline at (#{x_hit}, #{y_hit})" if print

        return XYCoordinates.new(x_hit, y_hit)
    end

    # Private
    def hit_detected(bc, print)
        if @coordinates.length > 1
            if has_hit_sideline(bc)
                puts "hit_detected - hit to a sideline detected (#{bc.x}, #{bc.y})" if print
                puts "-----------------------------------------------------------" if print
                return true
            elsif has_hit_goalline(bc)
                puts "hit_detected - hit to a goal-line detected (#{bc.x}, #{bc.y})" if print
                puts "-----------------------------------------------------------" if print
                return true
            elsif has_dxdy_changed_dramatically(bc)
                puts "hit_detected - dramatic change detected (#{bc.x}, #{bc.y})" if print
                puts "-----------------------------------------------------------" if print
                return true
            end
        end
        return false
    end

    # Private
    # Compares the given coordinates to latest added coordinates
    # Returns true, if the direction has changed
    def has_hit_sideline(bc)
        # If the sign of dy has changed, then the ball must have hit a sideline
        dy_future = bc.y - get_y
        keeps_same_direction = (dy_future < 0 && get_dy < 0) || (dy_future > 0 && get_dy > 0 )
        return ! keeps_same_direction
    end

    # Private
    def has_hit_goalline(bc)
        # If the sign of dx has changed, then the ball must have hit a sideline
        dx_future = bc.x - get_x
        keeps_same_direction = (dx_future < 0 && get_dx < 0) || (dx_future > 0 && get_dx > 0 )
        return ! keeps_same_direction
    end

    # Private
    def has_dxdy_changed_dramatically(bc)
        dx_future = bc.x - get_x
        dy_future = bc.y - get_y
        dxdy_future = dx_future/dy_future

        # Maximum allowed difference in percent
        threshold = 0.02 # 2 percent

        dxdy_current = get_dx/get_dy
        difference = ( (dxdy_current/dxdy_future).abs - 1.0).abs
        return difference > threshold
    end


end
