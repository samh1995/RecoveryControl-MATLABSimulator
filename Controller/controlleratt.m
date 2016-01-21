function Control = controlleratt(state,iSim,timeInit,tStep,altitudeDes,eulerAnglesDes,Control,impactOccured,timeImpact, manualCmds)

global m g Ixx Iyy Izz u2RpmMat

%% Save inputs 
attRollDes = eulerAnglesDes(1);
attPitchDes = eulerAnglesDes(2);
attYawDes = eulerAnglesDes(3);

errAltitudePrev = Control.errAltitude;
errAltitudeDerivPrev = Control.errAltitudeDeriv;

errAttRollPrev = Control.errEuler(1);
errAttPitchPrev = Control.errEuler(2);
errAttYawPrev = Control.errEuler(3);
errAttYawDerivPrev = Control.errYawDeriv;

%% Determine Current Attitude
q = [state(10);state(11);state(12);state(13)]/norm(state(10:13));
R = quat2rotmat(q);
[roll, pitch, yaw] = quat2angle(q,'xyz');


%% Zhang 2014 Controller
%% Altitude Controller Parameters
Kpz = 2;%20; %Zhang x4 value = 1
Kiz = 0;%40;
Kdz = 0.4;

Kpvz = 1.6;%10; %Zhang x4 value = 2.8
Kivz = 60;%10; %Zhang x4 value = 4

% altitudeDerivSaturation = 3; %Zhang x4 value = 0.6

%% Heading Controller Parameters
Kpyaw = 1.2; %1.2
Kiyaw = 1; %1
Kdyaw = 0.2; %0.2

%% Attitude Controller Parameters
Kprp = 60; %Zhang x4 value = 7.2
Kirp = 0; %Zhang x4 value = 4
Kdrp = 6; %Zhang x4 value = 4.2

Kpvyaw = 1.8; %1.8 %Zhang x4 value = 2.8
Kivyaw = 0.2; %2 %Zhang x4 value = 4;
Kdvyaw = 0; %Zhang x4 value = 0;

if impactOccured == 0
    %% PID Altitude Controller
    errAltitude = altitudeDes - state(9);
    if iSim == timeInit
        errAltitudeIntegral = 0;
        errAltitudeDeriv = 0;    
    else
        errAltitudeIntegral = errAltitude + errAltitudePrev;
        errAltitudeDeriv = errAltitude - errAltitudePrev;
    end

    altitudeDerivDes = Kpz*errAltitude + Kiz*tStep*(errAltitudeIntegral)*0.5 + Kdz*(errAltitudeDeriv)/tStep;
    % if altitudeDerivDes < 0
    %     altitudeDerivDes = max([-altitudeDerivSaturation,altitudeDerivDes]);
    % else
    %     altitudeDerivDes = min([altitudeDerivDes,altitudeDerivSaturation]);
    % end

    errAltitudeDeriv = altitudeDerivDes - R(:,3)'*state(1:3);
    if iSim == timeInit
        errAltitudeDerivPrev = -errAltitudeDeriv;
    end

    altitudeAcc = Kpvz*errAltitudeDeriv + Kivz*tStep*(errAltitudeDerivPrev+errAltitudeDeriv)*0.5;
    u1 = m*R(3,3)*(altitudeAcc+g);

    %% PID Heading Controller
     % Yaw
    errAttYaw = attYawDes - yaw;

    if errAttYaw > pi
        errAttYaw = -(2*pi - errAttYaw);
    end

    if iSim == timeInit
        errYawIntegral = 0;
        errYawDeriv = 0;
    else
        errYawIntegral = errAttYaw + errAttYawPrev;
        errYawDeriv = errAttYaw - errAttYawPrev;
    end

    attYawDerivDes = Kpyaw*errAttYaw + Kiyaw*tStep*(errYawIntegral) + Kdyaw*(errYawDeriv)/tStep;  

    
else % Use experiment joystick commands to match controller thrust and attitude commands
    for k = max(size(manualCmds)):-1:1
        if iSim >= timeImpact + manualCmds(k).time    
            u1 = manualCmds(k).thrust;
            attRollDes = manualCmds(k).attEuler(1);
            attPitchDes = manualCmds(k).attEuler(2);
            attYawDerivDes = manualCmds(k).angVel(3);

            errAltitude = 0;
            errAltitudeDeriv = 0;
            errAttYaw = 0;

            break    
        end
    end
    
end


% 
%% Attitude Controller

errAttRoll = attRollDes - roll;
errAttPitch = attPitchDes - pitch;
errAttYawDeriv = attYawDerivDes - state(6);

if iSim == timeInit
    errRollIntegral = 0;
    errPitchIntegral = 0;
    errYawDerivIntegral = 0;

    errRollDeriv = 0;
    errPitchDeriv = 0;
    errYawDerivDeriv = 0;
else
    errRollIntegral = errAttRoll + errAttRollPrev;
    errPitchIntegral = errAttPitch + errAttPitchPrev;
    errYawDerivIntegral = errAttYawDeriv + errAttYawDerivPrev;

    errRollDeriv = errAttRoll - errAttRollPrev;
    errPitchDeriv = errAttPitch - errAttPitchPrev;
    errYawDerivDeriv = errAttYawDeriv - errAttYawDerivPrev;
end

rollDeriv = Kprp*errAttRoll + Kirp*tStep*(errRollIntegral)*0.5 + Kdrp*(errRollDeriv)/tStep;
pitchDeriv = Kprp*errAttPitch + Kirp*tStep*(errPitchIntegral)*0.5 + Kdrp*(errPitchDeriv)/tStep;
yawDerivDeriv =  Kpvyaw*errAttYawDeriv + Kivyaw*tStep*(errYawDerivIntegral)*0.5 + Kdvyaw*(errYawDerivDeriv)/tStep;

u2 = (rollDeriv - state(5)*state(6)*(Iyy-Izz)/Ixx)*Ixx;
u3 = (pitchDeriv - state(4)*state(6)*(Izz-Ixx)/Iyy)*Iyy;
u4 = (yawDerivDeriv - state(4)*state(5)*(Ixx-Iyy)/Izz)*Izz;

%% Generate Control Signal
%Thrust and Moment Control Signal
u = [u1;u2;u3;u4];

%Propeller RPM Control Signal
temp = u2RpmMat*u;
rpmsquare = temp.*(temp>0);
rpm = max(min(sqrt(rpmsquare),6500),4000);
rpm = [-rpm(1);rpm(2);-rpm(3);rpm(4)]; %in RPM

% % Saturate propeller acceleration
% 
% prop_accel = zeros(4,1);
% prop_accel(1) = min(abs(omegadot(1)),prop_accel_sat)*sign(omegadot(1));
% prop_accel(2) = min(abs(omegadot(2)),prop_accel_sat)*sign(omegadot(2));
% prop_accel(3) = min(abs(omegadot(3)),prop_accel_sat)*sign(omegadot(3));
% prop_accel(4) = min(abs(omegadot(4)),prop_accel_sat)*sign(omegadot(4));
% 
% % Recalculate prop speed based on saturated propeller acceleration
% omegadot = prop_accel;
% omega_rad = omegadot*tStep + omega_prev_rad;
% omega = omega_rad * (60/(2*pi));

%% Assign values to output Control
Control.rpm = rpm;
Control.errAltitude = errAltitude;
Control.errAltitudeDeriv = errAltitudeDeriv;
Control.errEuler = [errAttRoll; errAttPitch; errAttYaw];
Control.errYawDeriv = errAttYawDeriv;
Control.twist.angVel(3) = attYawDerivDes;
Control.u = [u1;u2;u3;u4];


end

