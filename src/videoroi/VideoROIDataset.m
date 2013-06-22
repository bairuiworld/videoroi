classdef VideoROIDataset < handle
%
% Loads a dataset and performs rudimentary analysis (e.g. saccade detection
%  and conversion into angles).
%

    properties(Access = private)
        datasetInfo;

        % Screen distance, dimensions and resolution
        screen;

        taskName = '';
        
        % Data from eye-tracker
        header;
        data;
    end


    methods(Access = public)


        function obj = VideoROIDataset(datasetInfo, taskName)
            obj.taskName = taskName;
            obj.datasetInfo = datasetInfo;
            obj.loadCache();

            scr = [];
            scr.distance = 500;
            scr.resolution = [1024 768];
            scr.dimensions = [403 305];

            obj.defineScreen(scr);
        end
        
      
        function ppd = pixelsPerDegree(obj)
            lengthperdeg = tan(degtorad(1)) * obj.screen.distance;
            ppd = lengthperdeg / obj.screen.dimensions(1) * obj.screen.resolution(1);
        end        
        
        
        function defineScreen(obj, screen)
            % Set screen properties for calibration
            
            obj.screen = screen;
            obj.updateGazeCoordinates();
            obj.annotateTrace();
        end
        
        
        function count = getNumberOfTrials(obj)
            count = length(obj.data);
        end
        
        
        function list = getTrialsWithStimulus(obj, stimulusName)
            % List the trials in which a given stimulus is presented
            
            list = [];
            
            for t = 1:length(obj.data)
                for s = 1:length(obj.data(t).stimulus)
                    
                    [~, name, ~] = fileparts(obj.data(t).stimulus(s).name);
                    
                    if strcmpi(name, stimulusName)
                        list(end + 1) = t;
                        break;
                    end                    
                end
            end
        end
        
        
        function stimuli = getStimuliForTrial(obj, trialId)
            stimuli = obj.data(trialId).stimulus;
        end
        
        
        function [samples, columns] = getAnnotationsForTrial(obj, trialId)
            [samples, columns] = obj.getAnnotationsForInterval(trialId, -Inf, Inf);
        end
                       
        
        function [samples, columns] = getAnnotationsForFrame(obj, trialId, frameNr)
            sel = cellfun(@(x) ~isempty(x) && x == frameNr, {obj.data(trialId).stimulus.frame});            
            [samples, columns] = obj.getAnnotationsForInterval(trialId, obj.data(trialId).stimulus(sel).onset, obj.data(trialId).stimulus(sel).offset);
        end

        
        function [samples, columns] = getAnnotationsForInterval(obj, trialId, first, last)
            dta = obj.data(trialId);
            
            columns = {'Time', 'R POR X [px]', 'R POR Y [px]'};
            cols = idf_find_columns(columns, obj.header);
            
            columns{end + 1} = 'Fixation mask';
            columns{end + 2} = 'Saccade mask';
            
            % Handle infinity (i.e. from beginning or until end)
            if(isinf(first)), first = 1; end;
            if(isinf(last)), last = size(dta.samples, 1); end;
            
            intervalMask = first:last;
            
            samples = [dta.samples(intervalMask, cols), dta.fixation_mask(intervalMask), dta.saccade_mask(intervalMask)];
        end
        
    end
    

    methods(Access = private)
        
        %%%%%%%%%
        % Cache %
        %%%%%%%%%


        function generateCache(obj)
            % Regenerate cache
            
            cacheFile = fullfile(obj.datasetInfo.resourcepath, 'cache.dat');
            sourceFile = fullfile(obj.datasetInfo.resourcepath, obj.datasetInfo.filename);
                
            [s, m, header] = read_idf(sourceFile);
            data = idf_split_trials(s, m);
            
            % Perform task specific message parsing
            if(~isempty(obj.taskName))
                task = VideoROITaskFactory.obtainTaskInstance(obj.taskName);            
                data = task.parseStimulusMsgs(data);
            end
            
            taskName = obj.taskName;
            
            version = 2;

            save(cacheFile, 'version', 'header', 'data', 'taskName');
        end

        
        function loadCache(obj)
            % Load raw data from cache
            
            cacheFile = fullfile(obj.datasetInfo.resourcepath, 'cache.dat');
            
            % Generate cache if it does not already exist
            if(~exist(cacheFile, 'file'))
                obj.generateCache();
            end

            % Attempt to load cache file
            tmp = load(cacheFile, '-mat');
            
            % If the cache-version is not correct, regenerate
            if(tmp.version ~= 2)
                obj.generateCache();
                tmp = load(cacheFile, '-mat');
            end

            % Task has changed
            if(~isfield(tmp, 'taskName') || ~strcmp(tmp.taskName, obj.taskName))
                obj.generateCache();
                tmp = load(cacheFile, '-mat');
            end
            
            % Store data in a property            
            obj.header = tmp.header;
            obj.data = tmp.data;
        end
        
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Coordinate transformations %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        
        function updateGazeCoordinates(obj)
            % Update gaze coordinates given screen information

            if(~isstruct(obj.data)), return; end;
            if(~isstruct(obj.screen)), return; end;

            cfg = [];
            cfg.src = {'R POR X [px]', 'R POR Y [px]'};
            cfg.dest = {'R Gaze X [rad]', 'R Gaze Y [rad]'};

            cfg.procfcn = @(cfg, src) [ ...
                atan2(obj.screen.distance, (src(:, 1) ./ obj.screen.resolution(1) - 0.5) .* obj.screen.dimensions(1)) - 0.5 * pi, ...
                atan2(obj.screen.distance, (src(:, 2) ./ obj.screen.resolution(2) - 0.5) .* obj.screen.dimensions(2)) - 0.5 * pi];

            [obj.data, obj.header] = idf_transform_data(cfg, obj.data, obj.header);
        end
        
        
        %%%%%%%%%%%%%%
        % Annotation %
        %%%%%%%%%%%%%%
        
        
        function saccades = findSaccades(~, time, data, saccade_threshold, extension_angle_threshold)                        
            delta_t = diff(time);
            delta_s = diff(data);

            dsdt = delta_s ./ delta_t(1);
            speed = sqrt(sum(dsdt .^ 2, 2));

            % Apply speed threshold to find saccades
            saccade_mask = ...
                ([0; speed] > saccade_threshold) | ...
                ([speed; 0] > saccade_threshold);

            saccades = idf_cluster_mask(saccade_mask);

            % Extend clusters if angle is similar and 
            %  speed is decreasing.
            for c = 1:size(saccades, 1)                
                running = 1;
                while(running && saccades(c, 1) > 1)
                    previous = dsdt(saccades(c, 1) - 1, :);
                    current = dsdt(saccades(c, 1), :);
                
                    angle = atan2(previous(2), previous(1)) - atan2(current(2), current(1));
                    angle = mod(angle + pi, 2 * pi) - pi;
                
                    angle_crit = abs(angle) < extension_angle_threshold;
                    speed_crit = speed(saccades(c, 1) - 1) < speed(saccades(c, 1));
                
                    if(angle_crit && speed_crit)
                        saccades(c, 1) = saccades(c, 1) - 1;
                    else
                        running = 0;
                    end
                end
                
                running = 1;
                while(running && saccades(c, 2) < length(saccade_mask) - 1)
                    current = dsdt(saccades(c, 2) - 1, :);
                    next = dsdt(saccades(c, 2), :);
                    
                    angle = atan2(next(2), next(1)) - atan2(current(2), current(1));
                    angle = mod(angle + pi, 2 * pi) - pi;
                
                    angle_crit = abs(angle) < extension_angle_threshold;
                    speed_crit = speed(saccades(c, 2) - 1) > speed(saccades(c, 2));
                
                    if(angle_crit && speed_crit)
                        saccades(c, 2) = saccades(c, 2) + 1;
                    else
                        running = 0;
                    end                    
                end
            end
            
            % Todo: do we want to add an amplitude threshold?
        end        
        
        
        function annotateTrace(obj)
            % Detect saccades and fixations

            % Threshold in degrees per second
            saccade_threshold = degtorad(45);
            minimum_fixation_duration = 0.1; %100ms
            extension_angle_threshold = 0.5 * pi;
            
            col_gaze = idf_find_columns({'R Gaze X [rad]', 'R Gaze Y [rad]'}, obj.header);
            
            for t = 1:length(obj.data)
                time = obj.data(t).samples(:, 1) * 1e-6;
                gaze = obj.data(t).samples(:, col_gaze);
                
                saccades = obj.findSaccades(time, gaze, saccade_threshold, extension_angle_threshold); 
                saccade_mask = idf_mask_cluster(saccades, length(time));                
                
                % Fixations are not saccades
                fixation_mask = ~saccade_mask;                
                fixations = idf_cluster_mask(fixation_mask);

                % Remove fixation which do not meet minimum duration
                fixation_time = (time(2) - time(1)) * diff(fixations, [], 2);
                fixations(fixation_time < minimum_fixation_duration, :) = [];

                fixation_mask = idf_mask_cluster(fixations, length(time));
                
%                 if(t == 2)
%                     cla; hold on;
%                     plot(time-time(1), gaze(:, 1));
%                     
%                     masked_gaze = gaze(:, 1);
%                     masked_gaze(~fixation_mask) = NaN;
%                     plot(time-time(1), masked_gaze, 'r');
%                     
%                     masked_gaze = gaze(:, 1);
%                     masked_gaze(~saccade_mask) = NaN;
%                     plot(time-time(1), masked_gaze, 'g');
%                 end
                
                obj.data(t).saccade_mask = saccade_mask;
                obj.data(t).fixation_mask = fixation_mask;
            end
        end
        
    end
end