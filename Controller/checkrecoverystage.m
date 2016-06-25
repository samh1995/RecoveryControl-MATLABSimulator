function [recoveryStage] = checkrecoverystage(Pose, Twist, recoveryStage)

% Change to check quaternion error roll pitch elements
    attitudeStable = Pose.attEuler(1) < 0.2 && Pose.attEuler(2) < 0.2 ...
            && Twist.angVel(1) < 0.2  && Twist.angVel(2) < 0.2 && Twist.angVel(3) < 0.2;
        
    zVelocityStable = Twist.linVel(3) < 0.1;
    
    % accRef will follow fuzzy logic until errQuat converges to zero -
    % stage 3
    % then accRef is put to zero and once errQuat reconverges to zero stage
    % 4 is entered, and once height converges stage 5 is reached. 
    
    % this design decision assumes a discrete movement of accRef to zero
    % but I think it should be continuous. Try out accRef converging
    % linearly to zero
    % once accRef == zero we have the desired convergence maneuver - like 1
    % second.
    
    % stage one: recovery maneuver has begun
    % stage two: accRef has gone to zero and attitude has converged
    % stage three: height converged - returned to normal flight. 
    
    % change stage two's condition to include that accRef = 0
    
    if recoveryStage == 1
        if (attitudeStable && zVelocityStable)
            recoveryStage = 3;
        elseif attitudeStable
            recoveryStage = 2;
        end
    elseif recoveryStage == 2
        if zVelocityStable
            recoveryStage = 3;
        end
    end
end