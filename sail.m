function [output] = sail(d,p)
%SAIL - Surrogate Assisted Illumination Algorithm
% Main run script of SAIL algorithm
%
% Syntax:  [output] = sail(p)   
%
% Inputs:
%    p - struct for hyperparameters, visualization, and data gathering
%    * - sail with no arguments to return default parameter struct
%
% Outputs:
%    output - output struct with fields:
%               cD: true cD values of all tested samples [Nx1 double]
%               cL: true cL values of all tested samples [Nx1 double]
%          fitness: true fitness values of all tested samples [Nx1 double]
%     inputSamples: genomes of all tested samples [NxM double]
%           gpDrag: GP cD predictor function 
%           gpLift: GP cL predictor function
%              map: MAP of precisely evaluated solutions
%           acqMap: MAP of optimal solutions for sampling
%          predMap: MAP of best predicted solutions
%          mapTrue: true values of predMap
%                p: parameter struct
%       
%
% Example: 
%    p = sail;                                  % Load default parameters
%    p.nTotalSamples = 60;                      % Edit default parameters
%    output = sail(p);                          % Run SAIL algorithm
%    viewMap(output.predMap.fitness, output.p)  % View results    
%
% Other m-files required: defaultParamSet
% Other submodules required: map-elites, gpml-wrapper airFoilTools
% MAT-files required: none
%
% See also: mapElites, runSail

% Author: Adam Gaier
% Bonn-Rhein-Sieg University of Applied Sciences (HBRS)
% email: adam.gaier@h-brs.de
% Nov 2016; Last revision: 27-Jan-2017

%------------- BEGIN CODE --------------

if nargin==0; output = defaultParamSet; return; end

%% Domain parameter (temporary)
% d.initialize = 'af_InitialSamples';
% d.dof = 10;
% d.express = p.express;
% d.base = p.base;
% d.preciseEvalFunction = p.preciseEvalFunction;
% d.preciseEvaluate = 'af_PreciseEvaluate';
% 
% d.gpParams(1)= paramsGP(d.dof); % Drag
% d.gpParams(2)= paramsGP(d.dof); % Lift
% d.createAcqFunction= 'af_CreateAcqFunc';
% d.varCoef = p.varCoef;
% d.muCoef = p.muCoef;
% 
% d.featureRes = p.featureRes;
% d.extraMapValues = {'cD','cL'};
% 
% d.validate = 'af_ValidateChildren';
% 
% d.saveData = 'af_RecordData';

%% 0 - Produce Initial Samples
[observation, value] = feval(d.initialize,d,p.nInitialSamples);
nSamples = size(observation,1);

%% Acquisition Loop
% 1) Surrogate models are created from all evaluated samples, and these
% models are used to produce an acquisition function. 

% 2) A MAP is  constructed using the  evaluated samples are tested with the
% acquisition function and placed in a map as the initial population.

% 3) An illumination map is created by running MAP-Elites to optimize to
% acquisition function in every cell.

    % 3.2) When analyzing the performance of the algorithm, a prediction
    % map is created from the current models, and the accuracy of that
    % prediction is judged by evaluating all solutions. The frequency of
    % this process can be changed by changing the p.data parameters.
    
% 4) The next samples to be tested are chosen from the acquisition map,
% this is done with a sobol sequence to even sample the map in the feature
% dimensions. When evaluated solutions don't converge the next in bin in
% the sobol set is chosen.

while nSamples <= p.nTotalSamples
    
    %% 1 - Create Surrogate and Acquisition Function
    disp(['PE ' int2str(nSamples) ' | Training Surrogate Models']); 
    parfor iModel = 1:size(value,2)
       gpModel{iModel} = trainGP(observation, value(:,iModel), d.gpParams(iModel))
    end
    acqFunction = feval(d.createAcqFunction, gpModel, d);                                         
    
    %% 2 - Initialize MAP with Initial Samples
    % Evaluate data set with acquisition function
    [fitness,predValues] = acqFunction(observation);
    
    % Place Best Samples in Map with Predicted Fitness
    obsMap = createMap(d.featureRes, d.dof, d.extraMapValues);
    [replaced, replacement] = nicheCompete(observation, fitness, obsMap, d);
    obsMap = updateMap(replaced,replacement,obsMap,fitness,observation,...
                        predValues,d.extraMapValues);
       
    %% 3 - Illuminate Acquisition Map
    disp(['PE: ' int2str(nSamples) '| Illuminating Acquisition Map']);
    acqMap = mapElites(acqFunction,obsMap,p,d);

    %% 3.2 - Save data for Analysis
    %feval(d.saveData);

    %% 4 - Select Infill Samples
    if nSamples == p.nInitialSamples    % Initialize sobol sequence for sample selection
        sobSet  = scramble(sobolset(d.nDims,'Skip',1e3),'MatousekAffineOwen');
        sobPoint= 1;
    end   
    if nSamples == p.nTotalSamples; break; else % On Final illumination, no infill
                      
    newValue = nan(p.nAdditionalSamples, length(d.featureRes)); % new values will be stored here
    noValue = any(isnan(newValue),2);
    
    while any(any(noValue))
        nNans = sum(noValue);
        nextGenes = nan(nNans,d.dof); % Create one 'blank' genome for each NAN
        
        % Identify (grab indx of NANs)
        nanIndx = 1:p.nAdditionalSamples;  nanIndx = nanIndx(noValue);
        
        % Replace with next in Sobol Sequence
        newSampleRange = sobPoint:(sobPoint+nNans-1);
        mapLinIndx = sobol2indx(sobSet,newSampleRange,d, acqMap.edges);
        [chosenI,chosenJ] = ind2sub(d.featureRes, mapLinIndx);
        for iGenes=1:nNans % Pull out chosen genomes from map
            nextGenes(iGenes,:) = acqMap.genes(chosenI(iGenes),chosenJ(iGenes),:);
        end
        
        % Evaluate
        measuredValue = feval(d.preciseEvaluate, nextGenes, d);
        
        % Assign found values
        newValue(nanIndx,:) = measuredValue;
        noValue = any(isnan(newValue),2);
        nextObservation(nanIndx,:) = nextGenes;         %#ok<AGROW>
        sobPoint = sobPoint + length(newSampleRange);   % Increment sobol sequence for next samples
    end
    
    % Add Precise Evaluation Results to Data Set
    value = cat(1,value,newValue);
    observation = cat(1,observation,nextObservation);
    nSamples  = size(observation,1); 
    end   
end % end acquisition loop

output.p = p;
output.model = gpModel;
end %%end function





