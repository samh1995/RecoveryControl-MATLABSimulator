tic
clear all
global m g Kt timeImpact globalFlag

%% Initialize Simulation Parameters
ImpactParams = initparams_navi;

SimParams.recordContTime = 0;
SimParams.useFaesslerRecovery = 1;%Use Faessler recovery
SimParams.useRecovery = 1; 
SimParams.timeFinal = 2;
SimParams.timeInit = 0;
tStep = 1/200;

num_iter = 3;

%% Fake initialize everything for Monte Carlo struct to initialize
IC = initIC;
Control = initcontrol;
PropState = initpropstate;
Setpoint = initsetpoint;
[Contact, ImpactInfo] = initcontactstructs;
localFlag = initflags;
[state, stateDeriv] = initstate(IC);
[Pose, Twist] = updatekinematics(state, stateDeriv);
rotMat = quat2rotmat(Pose.attQuat);
Sensor = initsensor(rotMat, stateDeriv, Twist);
Hist = inithist(SimParams.timeInit, state, stateDeriv, Pose, Twist, Control, PropState, Contact, localFlag, Sensor);

% Initialize Monte Carlo Struct which holds all histories of each trial
Monte = initmontecarlo(0, IC, Hist);

for k = 1:num_iter
    k
    % randomize wall location for 3 angles 
    % g/2 0.37 < wallLoc < 0.70
    % g/3 0.45 < wallLoc < 0.9
    % g/4 0.50 < wallLoc < 1.1
    
    ImpactParams.wallLoc = rand*0.33 + 0.37;
    ImpactParams.wallPlane = 'YZ';
    ImpactParams.timeDes = 0.5;
    ImpactParams.frictionModel.muSliding = 0.3;
    ImpactParams.frictionModel.velocitySliding = 1e-4; %m/s
    timeImpact = 10000;

    %% Initialize Structures
    IC = initIC;
    Control = initcontrol;
    PropState = initpropstate;
    Setpoint = initsetpoint;
    [Contact, ImpactInfo] = initcontactstructs;
    localFlag = initflags;

    %% Set initial Conditions
    IC.attEuler = [0;deg2rad(0);deg2rad(0)];
    IC.posn = [0;0;5];
    IC.linVel = [0;0;0];
    IC.friction = ImpactParams.frictionModel.muSliding;
    rotMat = quat2rotmat(angle2quat(-(IC.attEuler(1)+pi),IC.attEuler(2),IC.attEuler(3),'xyz')');

    % not used --->
    Experiment.propCmds = [];
    Experiment.manualCmds = []; 
    globalFlag.experiment.rpmChkpt = zeros(4,1);
    globalFlag.experiment.rpmChkptIsPassed = zeros(1,4); % <-------

    %Start with hovering RPM ---- is this overkill now?
    IC.rpm = [-1;1;-1;1].*repmat(sqrt(m*g/(4*Kt)),4,1);  
    PropState.rpm = IC.rpm;

    %% Initialize state and kinematics structs from ICs
    [state, stateDeriv] = initstate(IC);
    [Pose, Twist] = updatekinematics(state, stateDeriv);

    %% Initialize sensors
    Sensor = initsensor(rotMat, stateDeriv, Twist);

    %% Initialize History Arrays
    Hist = inithist(SimParams.timeInit, state, stateDeriv, Pose, Twist, Control, PropState, Contact, localFlag, Sensor);

    %% Simulation Loop
    for iSim = SimParams.timeInit:tStep:SimParams.timeFinal-tStep

        % ! not using  ------>
        rotMat = quat2rotmat(Pose.attQuat);
        Sensor.accelerometer = (rotMat*[0;0;g] + stateDeriv(1:3) + cross(Twist.angVel,Twist.linVel))/g; %in g's
        Sensor.gyro = Twist.angVel; % <------

        %% Control

        % Before impact
        if ImpactInfo.firstImpactOccured == 0
            % give all four rpms equal divided by incoming angle cosine
        else
            Control = checkrecoverystage(Pose, Twist, Control, ImpactInfo);
            Control = computedesiredacceleration(Control, Twist);    
            Control = controllerrecovery(tStep, Pose, Twist, Control);   
        end

        %% Propagate dynamics
        options = getOdeOptions();
        [tODE,stateODE] = ode45(@(tODE, stateODE) dynamicsystem(tODE,stateODE, ...
                                                                tStep,Control.rpm,ImpactParams,PropState.rpm, ...
                                                                Experiment.propCmds),[iSim iSim+tStep],state,options);
        %% Contact recording

        % Reset contact flags for continuous time recording        
        globalFlag.contact = localFlag.contact;

        % if NOT recording contact times
        if SimParams.recordContTime == 0
            [stateDeriv, Contact, PropState] = dynamicsystem(tODE(end),stateODE(end,:), ...
                                                            tStep,Control.rpm,ImpactParams, PropState.rpm, ...
                                                            Experiment.propCmds);        
            if sum(globalFlag.contact.isContact)>0
                Contact.hasOccured = 1;
                if ImpactInfo.firstImpactOccured == 0
                    ImpactInfo.firstImpactOccured = 1;
                end
            end
        else  
             for j = 1:size(stateODE,1)
                [stateDeriv, Contact, PropState] = dynamicsystem(tODE(j),stateODE(j,:), ...
                                                                 tStep,Control.rpm,ImpactParams, PropState.rpm, ...
                                                                 Experiment.propCmds);            
                if sum(globalFlag.contact.isContact)>0
                    Contact.hasOccured = 1;
                    if ImpactInfo.firstImpactOccured == 0
                        ImpactInfo.firstImpactOccured = 1;
                    end
                end     
                ContHist = updateconthist(ContHist,stateDeriv, Pose, Twist, Control, PropState, Contact, globalFlag, Sensor); 
            end
            ContHist.times = [ContHist.times;tODE];
            ContHist.states = [ContHist.states,stateODE'];    
        end

        localFlag.contact = globalFlag.contact;     
        state = stateODE(end,:)';
        t = tODE(end);

        [Pose, Twist] = updatekinematics(state, stateDeriv);
        Hist = updatehist(Hist, t, state, stateDeriv, Pose, Twist, Control, PropState, Contact, localFlag, Sensor);
    end

    Monte = updatemontecarlo(k, IC, Hist, Monte);

end
%%
Monte.trial = Monte.trial(2:end);
Monte.IC = Monte.IC(2:end);
Monte.hist = Monte.hist(2:end);
Plot = monte2plot(Monte);

%%
% Plot XZ trajectories
% hold on;
% for k = 1:num_iter
%     plot(Plot.times,Monte(3,:,k))
% end

% animate(0,Hist,'ZX',ImpactParams,timeImpact,[])

% compute speed at impact 
%  Plot.posnDerivs(:,vlookup(Plot.times,timeImpact))
