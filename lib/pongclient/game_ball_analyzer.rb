class GameBallAnalyzer

    # Public
    SIDELINE_HIT_OFFSET = 1.0

    def initialize(client)
        @pitch = client.pitch

        # Contains the current ball coordinates
        # Cleared after hits to sidelines, goallines or paddles
        @coordinates = Array.new
    end

    def clear_coordinates
        @coordinates.clear
    end

    # Public
    def add_coordinates(bc, print=false)
        if hit_detected(bc, print)
            clear_coordinates
        end
        @coordinates.push(bc)
    end

    # Public
    # to_our_goal is boolean if we want to calculate pass coordinates to our goal-line
    # or their goal-line
    # TODO Refactor
    # Remove needless code repetition (give_simulated_pass_coordinates)
    # Code quality awful, but probably not time to redesign it.
    def give_pass_coordinates(to_our_goal, print=false)
        if ! is_enough_data
            $logger.debug "testi give_pass_coordinates: Ei tarpeeksi dataa" if print
            return false
        end

        if to_our_goal && ! is_going_towards_our_goalline
            $logger.debug "give_pass_coordinates: Ball is going the other way" if print
            return false
        elsif ! to_our_goal && is_going_towards_our_goalline
            $logger.debug "give_pass_coordinates: Ball is going the other way" if print
            return false
        end

        if to_our_goal && get_x < @pitch.get_our_goalline
            $logger.debug "give_pass_coordinates: Damn, the ball has passed our goalline" +
                 "(#{get_x}, #{get_y} #{get_dxdy}" if print
            #return false # as it's never too late to try
        end

        x_start = get_x
        y_start = get_y
        dx = get_dx
        dy = get_dy
        sideline_hits = 0

        # Recursive loop to get the last sideline hit before hitting our goal-line
        begin
            sideline_coords = calculate_sideline_hit(x_start, y_start, dx, dy, to_our_goal, print)
            if sideline_coords != false
                x_start = sideline_coords.x
                y_start = sideline_coords.y
                dy *= -1.0
                
                # Not used when ! to_our_goal
                sideline_hits += 1
                comes_from_up = y_start < @pitch.get_center_y

            end
        end while sideline_coords != false

    
        # If there's no sideline hits,
        # the current direction determines if it'll come from up
        if sideline_hits == 0
            ball_will_come_from_up = get_dy > 0
        else
            ball_will_come_from_up = comes_from_up
        end
        
        hit_coords = calculate_goalline_pass(x_start, y_start, dx, dy, to_our_goal, print)
        $logger.debug "testi actual hit_coords #{hit_coords.x} #{hit_coords.y}"
        
        return XYDCoordinates.new(hit_coords.x, hit_coords.y, ball_will_come_from_up)
    end

    # Public
    # Give pass coordinates using simulated data
    # TODO refactor and remove needless code repetition (give_pass_coordinates)
    def give_simulated_pass_coordinates(x_start, y_start, dx, dy, print=false)
        if ! is_enough_data
            $logger.debug "testi give_pass_coordinates: Ei tarpeeksi dataa" if print
            return false
        end

        to_our_goal = true
        
        # Recursive loop to get the last sideline hit before hitting our goalline
        begin
            $logger.debug "testi x= #{x_start} y= #{y_start}"
            sideline_coords = calculate_sideline_hit(x_start, y_start, dx, dy, to_our_goal, false)
            if sideline_coords != false
                x_start = sideline_coords.x
                y_start = sideline_coords.y
                dy *= -1.0
            end
        end while sideline_coords != false
        
        hit_coords = calculate_goalline_pass(x_start, y_start, dx, dy, to_our_goal, false)
        
        $logger.debug "testi simulated hit_coords #{hit_coords.x} #{hit_coords.y}"
        return hit_coords
    end
    
    # Public
    # Returns boolean if the ball is currently going towards our goal-line
    def is_going_towards_our_goalline
        if @coordinates.length < 2
            return false
        else
            return get_dx < 0
        end
    end

    # Public?
    def print_info
        if @coordinates.length == 1
            $logger.info sprintf("Current x: %6.2f, y: %6.2f", get_x, get_y)
        elsif @coordinates.length > 1
            $logger.info sprintf("Current x: %6.2f, y: %6.2f| dx: %8.3f, dy %8.3f| dx/dy: %8.3f", get_x, get_y, get_dx, get_dy, get_dx/get_dy)
        end
    end

    # Public
    def is_enough_data
        return @coordinates.length >= 2
    end

    # Public
    def get_dxdy
        return get_dx/get_dy
    end

    # Public
    # Returns the ball's latest x-coordinate
    def get_x
        return @coordinates[-1].x
    end

    # Public
    # Returns the ball's latest y-coordinate
    def get_y
        return @coordinates[-1].y
    end

    # Public
    def get_dx
        # x1 is before x2 in time
        x_1 = @coordinates[0].x
        x_2 = @coordinates[-1].x
        return x_2-x_1
    end

    # Public
    def get_dy
        y_1 = @coordinates[0].y
        y_2 = @coordinates[-1].y
        return y_2-y_1
    end

    # Public
    def get_dt
        t_1 = @coordinates[0].t
        t_2 = @coordinates[-1].t
        return t_2-t_1
    end

    private # --------------------------------------------------------------------

    def calculate_sideline_hit(x_start, y_start, dx, dy, to_our_goal, print)
        if dy < 0
            y_hit = @pitch.top_sideline_with_offset + @pitch.ball_radius
        else
            y_hit = @pitch.bottom_sideline_with_offset - @pitch.ball_radius
        end

        # The distance to travel in y before hit
        y_distance = (y_hit - y_start).abs
        dx_dy = (dx/dy).abs
        
        if ! to_our_goal
            dx_dy *= -1
        end
        
        # x_hit is the extrapolated value after travelling the x_distance
        x_hit =  x_start - dx_dy * y_distance

        if to_our_goal && x_hit < @pitch.get_our_goalline + @pitch.ball_radius
            return false
        elsif ! to_our_goal && x_hit > @pitch.get_their_goalline - @pitch.ball_radius
            return false
        else
            $logger.debug "testi sideline #{to_our_goal} #{x_hit}"
            $logger.debug "Sideline hit at (#{x_hit}, #{y_hit})" if print
            return XYCoordinates.new(x_hit, y_hit)
        end
    end

    # Gives the coordinates where the ball will probably pass our goal-line
    def calculate_goalline_pass(x_start, y_start, dx, dy, to_our_goal, print)
        if to_our_goal
            x_hit = @pitch.get_our_goalline
        else
            x_hit = @pitch.get_their_goalline
        end

        # The distance to travel in x before hit
        x_distance = ( x_hit - x_start ).abs
        dx_dy = (dx/dy).abs
        
        # y_hit is the extrapolated value after travelling the x_distance
        if dy > 0
            y_hit = y_start + (1.0/dx_dy) * x_distance
        elsif
            y_hit = y_start - (1.0/dx_dy) * x_distance
        end

        $logger.debug "Will hit our goalline at (#{x_hit}, #{y_hit})" if print

        return XYCoordinates.new(x_hit, y_hit)
    end

    # Private
    def hit_detected(bc, print)
        if @coordinates.length > 1
            if has_hit_sideline(bc)
                $logger.debug "hit_detected - hit to a sideline detected (#{bc.x}, #{bc.y})" if print
                $logger.debug "-----------------------------------------------------------" if print
                return true
            elsif has_hit_goalline(bc)
                $logger.debug "hit_detected - hit to a goal-line detected (#{bc.x}, #{bc.y})" if print
                $logger.debug "-----------------------------------------------------------" if print
                return true
            elsif has_dxdy_changed_dramatically(bc)
                $logger.debug "hit_detected - dramatic change detected (#{bc.x}, #{bc.y})" if print
                $logger.debug "-----------------------------------------------------------" if print
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
