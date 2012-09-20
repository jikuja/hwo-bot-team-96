class AI

    private # -----------------------------------------------------------------

    # How much (in amounts of ball radius) should the inner hitting point be
    # inside the paddle
    INNER_SAFE_FACTOR = -0.4
    
    # How much (in amounts of ball radius) should the outer hitting point be
    # inside the paddle.
    # In correct physics, the inner and outer should be the same.
    # Treats the symptom, not the disease (because we don't know what it is).
    OUTER_SAFE_FACTOR = 1.2 # 1.5 This is the optimal value, DON'T CHANGE

    # How close (in amounts of ball radius) to the sideline we allow our paddle to go.
    # With laggy connections the paddle might collide and bounce off
    # but it should be 0.0 if connection is perfect.
    SIDELINE_SAFE_FACTOR = 0.5 # For example 5 * 0.5 = 2.5 pixels
    public # ------------------------------------------------------------------

    # Public
    # Constructor
    def initialize(client)
        client = client
        @tcp = client.tcp
        @ball_analyzer = client.ball_analyzer
        @our_paddle = client.our_paddle_analyzer
        @their_paddle = client.their_paddle_analyzer
        @pitch = client.pitch
        @sma = client.sma

        # Coordinates where the ball will pass our goal-line
        @pass_y = 0.0
 
        # Coordinates where the paddle's center is aiming to go to
        @target_y = 0.0
        
        # The coordinates where the bot wants to aim its hit
        @where_to_aim_coordinates = XYCoordinates.new(480.0-10.0, 0.0)

        # The amount of uncertainty to pass coordinates that one sideline hit will cause
        @pixel_uncertainty_by_a_hit = 3.0 # +/- 3 pixels

        # How close (pixels) to the target coordinates we want to stop
        @target_distance_threshold = 0.5
        
        # How close (pixels) to the sideline we want to aim our hits.
        # Rather hit too near the center than hit a sideline.
        @aim_distance_from_sideline = 10.0

    end

    # Public
    # Main loop -- this is where everything happens
    def run
        while true
            sleep 0.01

            if @pitch.ready && @our_paddle.ready && @ball_analyzer.is_enough_coordinates
                # At the moment we take aim only once per ball.
                # The AI doesn't adapt to changes on the field when the ball
                # is coming our way
                update_target_coordinates
                speed = get_target_speed

                if (! @sma.is_same_speed(speed)) && (@sma.count_messages(2) < 19)
                    @sma.log_message(speed)
                    @tcp.puts movement_message(speed) + "\n"
                    $dumplogger.info(movement_message(speed) + "\n")
                else
                    #puts "ai.run: nothing we should or can do"
                end
            end
        end
    end

    private # -----------------------------------------------------------------

    # Private
    # Updates the coordinates where the paddle should go
    def update_target_coordinates

        update_where_to_aim_coordinates

        # Set the target to the center, if the ball is going the other way
        if ! @ball_analyzer.is_going_towards_our_goalline
            set_target_coordinates_to_center
            return
        end

        # Temp is used, because pass coordinates might return false
        # if there is not enough data after a sideline hit
        pass_coordinates = @ball_analyzer.give_pass_coordinates

        # Target coordinates temporarily not available -- use previous data
        if pass_coordinates != false
            @pass_y = pass_coordinates.y

            # What is the dx/dy-ratio we want to have after the ball has hit our paddle
            # (so it will reach the where_to_aim_coordinates)
            target_dxdy = calculate_dxdy(pass_coordinates, @where_to_aim_coordinates)

            # How many pixels from the center we want the ball to hit
            paddle_offset = get_offset(target_dxdy, @ball_analyzer.get_dxdy )

            # Reduce the offset because we don't want to take a too big risk
            puts "using offset #{paddle_offset} before limiting"
            #paddle_offset = adjust_offset_depending_on_uncertainty(paddle_offset)
            paddle_offset = limit_offset(paddle_offset)
            puts "using offset #{paddle_offset} after limiting"

            @target_y = pass_coordinates.y + paddle_offset
            limit_target_coordinates
        end
    end

    # Private
    # Update the where to aim coordinates
    def update_where_to_aim_coordinates
        
        if target_coordinates_can_be_hit_with_both_sides_of_paddle
            # TODO This makes the AI too predictable, but is it really a problem?
            # Shoots the ball into the corner that is easier to aim (do not try to
            # bounce the ball back to the direction where it comes from)
            if @ball_analyzer.ball_will_come_from_up
                # Opponent up, aim down
                puts "aim bottom"
                @where_to_aim_coordinates.y = @pitch.bottom_sideline - @aim_distance_from_sideline
            else
                # Opponent down, aim up
                puts "aim up"
                @where_to_aim_coordinates.y = @pitch.top_sideline + @aim_distance_from_sideline
            end
        else
            # Can't hit it freely. Plan B: Let's hit a sideline instead.
            if @ball_analyzer.ball_will_come_from_up
                if @pass_y < @pitch.get_center_y
                    # The ball bounces just from the sideline before hitting
                    # our paddle. We can't really aim in these situations.
                    aim_coordinates = XYCoordinates.new( @pitch.get_their_goalline, @pitch.get_center_y )
                else
                    # Hit the ball to the sideline
                    # TODO -- calculate the sideline coordinates
                    aim_coordinates = XYCoordinates.new(50.0, @pitch.bottom_sideline)
                end
            else
                if @pass_y > @pitch.get_center_y
                    # The ball bounces just from the sideline before hitting
                    # our paddle. We can't really aim in these situations.
                    aim_coordinates = XYCoordinates.new( @pitch.get_their_goalline, @pitch.get_center_y )
                else
                    # TODO -- calculate the sideline coordinates
                    # Hit the ball to the sideline
                    aim_coordinates = XYCoordinates.new(50.0, @pitch.top_sideline)
                end

            end
        end

        # for debug
        #@where_to_aim_coordinates.y = @pitch.top_sideline + distance_from_sideline
        #@where_to_aim_coordinates.y = @pitch.bottom_sideline - distance_from_sideline
        #@where_to_aim_coordinates.y = @pitch.get_center_y # this is dangerous
    end

    # Private
    # Reduces the amount of offset if the goalline pass coordinates have uncertainty
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
                
        puts "paddle_offset #{paddle_offset} total #{pixel_uncertainty_total}"
        
        return paddle_offset
    end

    # Private
    # Makes sure that the offset is not bigger than our limits.
    def limit_offset(paddle_offset)

        # This function should be rendered unnecessary.
        # Or it can be kept as an extra safety measure.

        # Let's not use the most outer pixels.
        # The amount depends on whether we are using the inner or outer side.
        max_inner_offset = @pitch.get_half_of_paddle_height - get_inner_safe_zone
        max_outer_offset = @pitch.get_half_of_paddle_height - get_outer_safe_zone
        puts "max #{max_outer_offset} #{max_inner_offset}"

        if ( @ball_analyzer.ball_will_come_from_up &&
             paddle_offset < 0 &&
             paddle_offset.abs > max_outer_offset )

            # Comes from up, will be hit with outer side
            paddle_offset = (-1)*max_outer_offset
            
        elsif (! @ball_analyzer.ball_will_come_from_up &&
                 paddle_offset > 0 &&
                 paddle_offset > max_outer_offset )

            # Comes from down, will be hit with outer side             
            paddle_offset = max_outer_offset

        elsif ( @ball_analyzer.ball_will_come_from_up &&
                paddle_offset > 0 &&
                paddle_offset > max_inner_offset )
            
            # Comes from up, will be hit with inner side
            paddle_offset = max_inner_offset
        
        elsif ( ! @ball_analyzer.ball_will_come_from_up &&
                paddle_offset < 0 &&
                paddle_offset.abs > max_inner_offset )
        
            # Comes from down, will be hit with inner side
            paddle_offset = (-1)*max_inner_offset
        else
            # The offset doesn't need limiting
            paddle_offset = paddle_offset
        end

        puts "limit_offset #{@ball_analyzer.ball_will_come_from_up} #{paddle_offset}"
        return paddle_offset
    end

    # Gives the speed that we wish our paddle will go
    def get_target_speed
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
                return calculate_adapted_speed*(-1)
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

    # Prevent the paddle from hitting a sideline
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
        # TODO change into one if-clause
        
        needed_change_of_dxdy = get_needed_dxdy_change(target_dxdy, current_dxdy)
        
        if target_dxdy > 0 && current_dxdy < 0
            # Ball comes from up, will move down (after bounce)

            if target_dxdy > current_dxdy.abs
                # We want to increase dxdy.
                # Move paddle down, hit with inner side.
                puts "bounce - up, down"                
                return (-1)*calculate_offset(needed_change_of_dxdy, current_dxdy, true)
            else
                # We want to decrease dxdy.
                # Move paddle up, hit with outer side.
                puts "bounce - up, up"
                return calculate_offset(needed_change_of_dxdy, current_dxdy, false)
            end
            
        elsif target_dxdy < 0 && current_dxdy > 0
            # Ball comes from below, will move up (after bounce)

            if target_dxdy.abs > current_dxdy
                # We want to increase dxdy.
                # Move paddle up, hit with inner side.
                puts "bounce - down, down"
                return (-1)*calculate_offset(needed_change_of_dxdy, current_dxdy, true)
            else
                # We want to decrease dxdy.
                # Move paddle down, hit with outer side.
                puts "bounce - down, down"                
                return calculate_offset(needed_change_of_dxdy, current_dxdy, false)
            end
        else
            # TODO what to do when this happens?
            # We want to bounce the ball to the same direction where it comes from
            # (this is very, very, very difficult or impossilbe)
            
            puts "error - unrealistic bouncing asked. we should not try this"
            return 0.0 # Just make a random hit
        end
    end

    # Private
    # How much we should change the angle when the ball hits our paddle.
    # This is deviation to the physical perpendicular surface hit.
    def get_needed_dxdy_change(wanted_dxdy, current_dxdy)

        if (wanted_dxdy < 0 && current_dxdy > 0) || (wanted_dxdy > 0 && current_dxdy < 0)
        # TODO Filter some impossible cases
            # If the certain bounce seems possible to do
            return (wanted_dxdy.abs - current_dxdy.abs).abs
        else
            # TODO
            # We can't do a hit like what was asked. Just hit it.
            puts "error - asked to bounce the ball back"
            return 5.0
        end
    end

    # Private
    # Does the magic. Calculates what distance/offset from paddle's
    # center gives the wanted change in dxdy. Uses absolute values.
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
        puts "change_dxdy need=#{needed_change_of_dxdy} cur=#{current_dxdy} offset=#{temp_offset}"
        return temp_offset
            
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

        if (  @ball_analyzer.ball_will_come_from_up &&   paddle_is_above_pass) ||
           (! @ball_analyzer.ball_will_come_from_up && ! paddle_is_above_pass)

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
        # TODO We could calculate the sector that is possible for the opponent
        # to hit, and move the paddle to the ofter of that sector.
        @target_y = @pitch.get_center_y
        @pass_y = @pitch.get_center_y
    end

    # Is it possible to hit the the ball with both sides of the paddle,
    # or is the coordinate too close to a sideline? 
    def target_coordinates_can_be_hit_with_both_sides_of_paddle
        if @target_y < @pitch.paddle_height - get_outer_safe_zone
            puts "cannot be hit with both sides"
            return false
        elsif @target_y > @pitch.bottom_sideline - @pitch.paddle_height + get_outer_safe_zone
            puts "cannot be hit with both sides"
            return false
        else
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
    def movement_message(delta)
        %Q!{"msgType":"changeDir","data":#{delta}}!
    end

end

