class AI

    private # -----------------------------------------------------------------

    # How much (in amounts of ball radius) should the inner hitting point be
    # inside the paddle
    INNER_SAFE_FACTOR = 0.1
    
    # How much (in amounts of ball radius) should the outer hitting point be
    # inside the paddle.
    # In correct physics, the inner and outer should be the same.
    # Treats the symptom, not the disease (because we don't know what it is).
    OUTER_SAFE_FACTOR = 1.1

    # How close (in amounts of ball radius) to the sideline we allow our paddle to go.
    # With laggy connections the paddle might collide and bounce off
    # but it should be 0.0 if connection is perfect.
    SIDELINE_SAFE_FACTOR = 0.5 # For example 5 * 0.5 = 2.5 pixels
    public # ------------------------------------------------------------------

    # Public
    # Constructor
    def initialize(client)
        @tcp = client.tcp
        @ball_analyzer = client.ball_analyzer
        @our_paddle = client.our_paddle_analyzer
        @their_paddle = client.their_paddle_analyzer
        @pitch = client.pitch
        @sma = client.sma
        @log_message = "ai3.rb: "

        # Coordinates where the ball will pass our goal-line
        @pass_y = 0.0
 
        # Coordinates where the paddle's center is aiming to go to
        @target_y = 0.0
        
        # The coordinates where the bot wants to aim its hit
        @where_to_aim_coordinates = XYCoordinates.new(600.0-10.0, 0.0)

        # The amount of uncertainty to pass coordinates that one sideline hit will cause
        @pixel_uncertainty_by_a_hit = 2.0 # +/- 2.0 pixels

        # How close (pixels) to the target coordinates we want to stop
        @target_distance_threshold = 0.5
        
        # How close (pixels) to the sideline we want to aim our hits.
        # Rather hit too near the center than hit a sideline, because after a hit
        # it will bounce near the center and travel longer time.
        @aim_distance_from_sideline = 50.0

        # If the paddle is currently moved based on a guess
        @guess_mode = false
    end

    # Public
    # Main loop -- this is where everything happens
    def run
        while true
            sleep 0.01

            if @pitch.ready && @our_paddle.ready && @ball_analyzer.is_enough_data
                # At the moment we take aim only once per ball.
                # The AI doesn't adapt to changes on the field when the ball
                # is coming our way
                update_target_coordinates
                speed = get_target_speed 
 
                if (! @sma.is_same_speed(speed) ) && ( @sma.count_messages(2) < 19 )
                    @sma.log_message(speed)
                    @tcp.puts movement_message(speed) + "\n"
                    $dumplogger.info(movement_message(speed))
                    $logger.debug @log_message
                else
                    #actually this is stupid: only one debug level in loggers!
                    #$logger.debug @log_message
                    @log_message = "ai3.rb: "
                end
            end
        end
    end

    private # -----------------------------------------------------------------

    # Private
    # Updates the coordinates where the paddle should go
    def update_target_coordinates


        # If the ball is going the other way
        # we try to optimize the paddle location
        if ! @ball_analyzer.is_going_towards_our_goalline
            if @ball_analyzer.is_enough_data
                # Calculate where to opponent is aiming to hit the ball,
                # move paddle there.
                @guess_mode = true
                set_target_coordinates_to_opponent_hit_zone
                return
            else
                # Normal defense mode. This should not happen very often.
                @guess_mode = false # This is basically a guess, but still
                set_target_coordinates_to_center
                return
            end
        end
        
        @guess_mode = false
        update_where_to_aim_coordinates

        # Temp is used, because pass coordinates might return false
        # if there is not enough data after a sideline hit
        pass_coordinates = @ball_analyzer.give_pass_coordinates(true)

        # Target coordinates temporarily not available -- use previous data
        if pass_coordinates != false
            @pass_y = pass_coordinates.y
            @ball_will_come_from_up = pass_coordinates.comes_from_up

            # What is the dx/dy-ratio we want to have after the ball has hit our paddle
            # (so it will reach the where_to_aim_coordinates)
            target_dxdy = calculate_dxdy(pass_coordinates, @where_to_aim_coordinates)

            # How many pixels from the center we want the ball to hit
            paddle_offset = get_offset(target_dxdy, @ball_analyzer.get_dxdy )

            # Reduce the offset because we don't want to take a too big risk
            @log_message += "\n" +  "using offset #{paddle_offset} before limiting"
            #paddle_offset = adjust_offset_depending_on_uncertainty(paddle_offset)
            paddle_offset = limit_offset(paddle_offset)
            @log_message += "\n" +  "using offset #{paddle_offset} after limiting"

            @target_y = pass_coordinates.y + paddle_offset
            limit_target_coordinates
        end
    end

    # Private
    # Update the where to aim coordinates
    def update_where_to_aim_coordinates
        
        # DO NOT try to bounce the ball back to the direction where it comes from

        # TODO if ball_y close to edges and get_dy.abs is small, we could shoot the ball back

        if pass_coordinates_can_be_hit_with_both_sides_of_paddle
            # Shoots the ball into the corner that is easier to aim
            if @ball_will_come_from_up
                # Aim down
                @log_message += "\n\t" +  "aim bottom"
                aim_x = @pitch.get_their_goalline
                aim_y = @pitch.bottom_sideline - @aim_distance_from_sideline
            else
                # Aim up
                @log_message += "\n\t" +  "aim up"
                aim_x = @pitch.get_their_goalline
                aim_y = @pitch.top_sideline - @aim_distance_from_sideline
            end
        else
            # Can't hit it freely. Plan B: Let's hit a sideline instead.
            if @ball_will_come_from_up
                if @pass_y < @pitch.get_center_y
                    # The ball bounces just from the sideline before hitting
                    # our paddle. We can't really aim in these situations.
                    @log_message += "\n\t" +  "aim center from top"
                    aim_x = @pitch.get_their_goalline
                    aim_y = @pitch.get_center_y
                else
                    # Hit the ball to the sideline
                    # TODO -- calculate the sideline coordinates
                    @log_message += "\n\t" +  "aim bottom sideline from top"
    
                    aim_x = 200.0
                    aim_y = @pitch.bottom_sideline
                end
            else
                if @pass_y > @pitch.get_center_y
                    # The ball bounces just from the sideline before hitting
                    # our paddle. We can't really aim in these situations.
                    @log_message += "\n\t" +  "aim center from bottom"
                    aim_x = @pitch.get_their_goalline
                    aim_y = @pitch.get_center_y
                else
                    # TODO -- calculate the sideline coordinates
                    # Hit the ball to the sideline
                    @log_message += "\n\t" +  "aim top sideline from bottom"
                    aim_x = 200.0
                    aim_y = @pitch.top_sideline
                end

            end
            
        end

        @where_to_aim_coordinates = XYCoordinates.new( aim_x, aim_y )

        # for debug
        #@where_to_aim_coordinates.y = @pitch.top_sideline + distance_from_sideline
        #@where_to_aim_coordinates.y = @pitch.bottom_sideline - distance_from_sideline
        #@where_to_aim_coordinates.y = @pitch.get_center_y
    end

    # Set our paddle target coordinates to where the opponent supposedly will hit
    # TODO Code quality awful, but probably not time to refactor it.
    def set_target_coordinates_to_opponent_hit_zone
                        
        # Where the ball will most likely pass opponent goal-line
        their_goalline_pass_coordinates = @ball_analyzer.give_pass_coordinates(false)
        
        
        # If the opponent has stopped, we can calculate where the ball will go after
        # a hit to their paddle.
        # If the opponent is moving, assume an offset 0 hit.
        
        if ! @their_paddle.is_moving
            # Where the opponent is located
            opponent_paddle_y = @their_paddle.get_y
            # Opponent offset from the calculated pass coordinates
            opponent_offset = their_goalline_pass_coordinates.y - opponent_paddle_y
        else
            opponent_offset = 0.0
        end

        if their_goalline_pass_coordinates.comes_from_up && opponent_offset > 0
            hit_with_inner = true
        elsif ! their_goalline_pass_coordinates.comes_from_up && opponent_offset < 0
            hit_with_inner = true
        else
            hit_with_inner = false
        end

        current_dxdy = @ball_analyzer.get_dxdy
        
        # Calculate bounced dxdy based on the offset
        change_in_dxdy = calculate_change_in_dxdy(opponent_offset, current_dxdy, hit_with_inner)
        change_in_dxdy = change_in_dxdy.abs
        
        if hit_with_inner
            change_in_dxdy *= -1
        end
        
        bounced_dxdy = current_dxdy.abs + change_in_dxdy
        bounced_dxdy = bounced_dxdy.abs
        
        $logger.debug "testi bounced #{bounced_dxdy}"
        
        x_start = their_goalline_pass_coordinates.x
        y_start = their_goalline_pass_coordinates.y
        
        # Only the relative values of dx and dy matter, so
        # divide bounced_dxdy into components with a dummy way 
        dx = (-1)*@ball_analyzer.get_dx.abs
        dy = dx/bounced_dxdy
        
        if their_goalline_pass_coordinates.comes_from_up 
            dy *= -1
        end
        
        pass_coordinates = @ball_analyzer.give_simulated_pass_coordinates(x_start, y_start, dx, dy, false)
    
        # Terrible fix to the problem
        if pass_coordinates != false
            # set target coordinates to there
            @target_y = pass_coordinates.y
            @pass_y  = pass_coordinates.y
        end
    end

    # Private
    # Reduces the amount of offset if the goalline pass coordinates have uncertainty
    # TODO Not used at the moment. Remove or start using it.
    def adjust_offset_depending_on_uncertainty(paddle_offset)
        future_sideline_hits = @ball_analyzer.get_future_sideline_hits

        pixel_uncertainty_total = @pixel_uncertainty_by_a_hit * future_sideline_hits

        # Move the paddle towards the center
        # TODO could take into account if covering area anyways
        if paddle_offset < 0
            paddle_offset += pixel_uncertainty_total
        else
            paddle_offset -= pixel_uncertainty_total            
        end
                
        @log_message += "\n\t" +  "paddle_offset #{paddle_offset} total #{pixel_uncertainty_total}"
        
        return paddle_offset
    end

    # Private
    # Makes sure that the offset is not bigger than our limits.
    def limit_offset(paddle_offset)

        # Let's not use the most outer pixels.
        # The amount depends on whether we are using the inner or outer side.
        max_inner_offset = @pitch.get_half_of_paddle_height - get_inner_safe_zone
        max_outer_offset = @pitch.get_half_of_paddle_height - get_outer_safe_zone
        @log_message += "\n\t" +  "max #{max_outer_offset} #{max_inner_offset}"

        if ( @ball_will_come_from_up &&
             paddle_offset < 0 &&
             paddle_offset.abs > max_outer_offset )

            # Comes from up, will be hit with outer side
            paddle_offset = (-1)*max_outer_offset
            
        elsif (! @ball_will_come_from_up &&
                 paddle_offset > 0 &&
                 paddle_offset > max_outer_offset )

            # Comes from down, will be hit with outer side             
            paddle_offset = max_outer_offset

        elsif ( @ball_will_come_from_up &&
                paddle_offset > 0 &&
                paddle_offset > max_inner_offset )
            
            # Comes from up, will be hit with inner side
            paddle_offset = max_inner_offset
        
        elsif ( ! @ball_will_come_from_up &&
                paddle_offset < 0 &&
                paddle_offset.abs > max_inner_offset )
        
            # Comes from down, will be hit with inner side
            paddle_offset = (-1)*max_inner_offset
        else
            # The offset doesn't need limiting
            paddle_offset = paddle_offset
        end

        @log_message += "\n\t" +  "limit_offset #{@ball_will_come_from_up} #{paddle_offset}"
        return paddle_offset
    end

    # Gives the speed that we wish our paddle will go
    def get_target_speed
        if @guess_mode
            return get_sloppy_speed
        else
            return get_intelligent_speed
        end
    end
    
    # Used to control the speed when it's not crucial to reach accurately
    # the target coordinates
    def get_sloppy_speed
        if paddle_is_in_risk_of_hitting_the_sideline
            # Stop the paddle before it hits the sideline
            return 0.0
        elsif paddle_is_covering_pass_coordinates
            return 0.0
        else
            if paddle_is_above_target
                # The paddle is far from the target and above it, full speed downwards
                return 1.0
            else
                # Full speed upwards
                return -1.0
            end
        end    
    end
    
    # Aims to reach the target coordinates accurately. Adapts speed when near the
    # target coordinates.
    def get_intelligent_speed
        if paddle_is_in_risk_of_hitting_the_sideline
            # Stop the paddle before it hits the sideline
            return 0.0
        elsif get_distance_to_target < @target_distance_threshold
            # The paddle is in the target coordinates, stop moving
            return 0.0
        elsif paddle_is_covering_pass_coordinates
            # The paddle is already covering the pass coordinates, 
            # but not at optimal distance, slower the speed
            if paddle_is_above_target
                return calculate_adapted_speed
            else
                return (-1)*calculate_adapted_speed
            end
        else
            if paddle_is_above_target
                # The paddle is far from the target and above it, full speed downwards
                return 1.0
            else
                # Full speed upwards
                return -1.0
            end
        end
    end

    # Helps preventing the paddle from hitting a sideline
    def paddle_is_in_risk_of_hitting_the_sideline
        return (  @our_paddle.get_y < sideline_safe_zone && @sma.speed < 0 ) ||
               ( (@our_paddle.get_y > @pitch.bottom_sideline + sideline_safe_zone ) &&
                 @sma.speed > 0 )
    end

    # We adapt the speed of the paddle to how far it is from target coordinates.
    # Speed is 1.0 if it's outside of cover area.
    # This function works within cover area, changing gradually from 0.9 to 0.1
    def calculate_adapted_speed
        speed_factor = 0.5 # let's slow it down a bit
        speed = get_distance_to_target/(@pitch.get_half_of_paddle_height)*speed_factor
               
        return ((speed*10).round)/10.0
    end

    # Manages the calculating of offset that will bounce ball at target dxdy
    def get_offset(target_dxdy, current_dxdy)
        
        needed_change_of_dxdy = get_needed_dxdy_change(target_dxdy, current_dxdy)
        
        if target_dxdy > 0 && current_dxdy < 0
            # Ball comes from up, will move down after bounce

            if target_dxdy > current_dxdy.abs
                # We want to increase dxdy.
                # Move paddle down, hit with inner side.
                @log_message += "\n\t" +  "bounce - up, down"                
                return calculate_offset(needed_change_of_dxdy, current_dxdy, true)
            else
                # We want to decrease dxdy.
                # Move paddle up, hit with outer side.
                @log_message += "\n\t" +  "bounce - up, up"
                return (-1)*calculate_offset(needed_change_of_dxdy, current_dxdy, false)
            end
            
        elsif target_dxdy < 0 && current_dxdy > 0
            # Ball comes from below, will move up after bounce

            if target_dxdy.abs > current_dxdy
                # We want to increase dxdy.
                # Move paddle up, hit with inner side.
                @log_message += "\n\t" +  "bounce - down, up"
                return (-1)*calculate_offset(needed_change_of_dxdy, current_dxdy, true)
            else
                # We want to decrease dxdy.
                # Move paddle down, hit with outer side.
                @log_message += "\n\t" +  "bounce - down, down"                
                return calculate_offset(needed_change_of_dxdy, current_dxdy, false)
            end
        else
            # TODO what to do when this happens?
            # This tries to hit the ball to the direction where it comes from.
            # It is very, very, very difficult.
            
            @log_message += "\n\t" +  "error - unrealistic bouncing asked"
            return 7.0 # Just try as hard as you can
        end
    end

    # Private
    # How much we should change the angle when the ball hits our paddle.
    # This is deviation to the physical perpendicular surface hit.
    def get_needed_dxdy_change(wanted_dxdy, current_dxdy)

        # In normal bounce the before and after dxdy are of different sign
        if (wanted_dxdy < 0 && current_dxdy > 0) || (wanted_dxdy > 0 && current_dxdy < 0)
            return (wanted_dxdy.abs - current_dxdy.abs).abs
        else
            # TODO
            # This should not happen.
            # We can't do a hit like what was asked. Just hit it.
            @log_message += "\n\t" +  "error - asked to bounce the ball back"
            return 3.0
        end
    end

    # Private
    # Does the magic. Calculates what offset from paddle's
    # center gives us the wanted change in dxdy. Uses absolute values.
    def calculate_offset(needed_change_of_dxdy, current_dxdy, hit_with_inner)
        current_dxdy = current_dxdy.abs
        
        if hit_with_inner
            a = 0.02
            b = 0.0
        else
            a = 0.05
            b = 0.0
        end

        temp_offset = needed_change_of_dxdy / (a * current_dxdy) - b / a        
        @log_message += "\n\t" +  "change_dxdy need=#{needed_change_of_dxdy} cur=#{current_dxdy} offset=#{temp_offset}"
        return temp_offset
            
    end

    # Private
    # Does the magic.
    # Reverse version of the function calculate_offset
    def calculate_change_in_dxdy(offset, current_dxdy, hit_with_inner)
        
        if hit_with_inner
            a = 0.02
            b = 0.0
        else
            a = 0.05
            b = 0.0
        end

        change_in_dxdy = offset*a*current_dxdy + b*current_dxdy
    
    
        return change_in_dxdy    
    end
    
    
    
    # Private
    # Return the distance between paddle's center and the target coordinates
    def get_distance_to_target
        return (@our_paddle.get_y-@target_y).abs
    end

    # Private
    # Return the distance between the paddle's center and the coordinates
    # where the ball passes our goal-line
    def get_distance_to_pass
        return (@our_paddle.get_y-@pass_y).abs
    end
    
    # Private
    # If the paddle with its height covers the target coordinates in its current location 
    def paddle_is_covering_pass_coordinates

        # The covering depends on whether the ball is (at the moment) going to hit
        # the inner or the outer side of the paddle.
        # This is due to the flow effect.

        if (  @ball_will_come_from_up &&   paddle_is_above_pass) ||
           (! @ball_will_come_from_up && ! paddle_is_above_pass)

            # Ball will hit the outer side of the paddle.
            # Take into account the flow effect
            return get_distance_to_pass + get_outer_safe_zone < @pitch.get_half_of_paddle_height
        else
            # Ball will hit the inner side of the paddle
            return get_distance_to_pass + get_inner_safe_zone < @pitch.get_half_of_paddle_height
        end
    end

    # Private
    # Sets the paddle's moving target coordinates to the center of the pitch
    def set_target_coordinates_to_center
        @target_y = @pitch.get_center_y
        @pass_y = @pitch.get_center_y
    end

    # Is it possible to hit the the ball with both sides of the paddle,
    # or is the coordinate too close to a sideline? 
    def pass_coordinates_can_be_hit_with_both_sides_of_paddle
        if @pass_y < @pitch.paddle_height - get_outer_safe_zone
            @log_message += "\n\t" +  "not hitable with both sides up"
            return false
        elsif @pass_y > @pitch.bottom_sideline - @pitch.paddle_height + get_outer_safe_zone
            @log_message += "\n\t" +  "not hitable with both sides down"
            return false
        else
            @log_message += "\n\t" +  "hitable"
            return true
        end
    end    

    def get_inner_safe_zone
        return @pitch.ball_radius*INNER_SAFE_FACTOR
    end
    
    def get_outer_safe_zone
        return @pitch.ball_radius*OUTER_SAFE_FACTOR
    end

    def sideline_safe_zone
        return SIDELINE_SAFE_FACTOR*@pitch.ball_radius
    end

    # We can't "reach" target coordinates that are too close to the edge, because
    # the paddle's coordinates are calculated from the its center.
    # This was rendered useless by stopping the paddle in get_speed
    def limit_target_coordinates
        if @target_y < @pitch.get_half_of_paddle_height
            @target_y = @pitch.get_half_of_paddle_height
        elsif @target_y > @pitch.bottom_sideline - @pitch.get_half_of_paddle_height
            @target_y = @pitch.bottom_sideline - @pitch.get_half_of_paddle_height
        end
    end

    # Above defined as "human above", ignoring inverted y-axis
    def paddle_is_above_target
        return @our_paddle.get_y < @target_y
    end

    # Above defined as "human above", ignoring inverted y-axis
    def paddle_is_above_pass
        return @our_paddle.get_y < @pass_y
    end

    # Arithmetic function without context
    def calculate_dxdy(from_coordinates, to_coordinates)
        delta_x = to_coordinates.x - from_coordinates.x
        delta_y = to_coordinates.y - from_coordinates.y
        
        return delta_x/delta_y
    end

    # Send the JSON-message to the server
    def movement_message(speed)
        %Q!{"msgType":"changeDir","data": #{speed}}!
    end

end

