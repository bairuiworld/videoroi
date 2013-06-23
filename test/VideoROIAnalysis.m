function VideoROIAnalysis(cfg)

    function cfg = fill_defaults(cfg)
    % FILL_DEFAULTS  Fills missing values in the configuration
    %  sturcture with their defaults.
        if(~isfield(cfg, 'projectDirectory'))
            cfg.projectDirectory = 'C:\Users\Ivar\Desktop\Project3_All';
        end
        
        if(~isfield(cfg, 'outputFile'))            
            cfg.outputFile = fullfile(cfg.projectDirectory, 'output.csv');
        end
    end


    function stimulus_info = get_stimulus_info(project, name)
    % GET_STIMULUS_INFO  Find and return information about the 
    % stimulus with name [name] in the specified project.
    
        n_stimuli = project.getNumberOfStimuli();

        for i_stimulus = 1:n_stimuli
            stimulus_info = project.getInfoForStimulus(i_stimulus);
            [~, sname, ~] = fileparts(stimulus_info.name);
            [~, name, ~] = fileparts(name);                
             
            if strcmpi(sname, name)     
                return;
            end    
        end
    
        stimulus_info = 0;
    end


    function perform_analysis_trial(cfg)
    % PERFORM_ANALYSIS_TRIAL  Peforms the analysis for a single trial only.
    
        [samples, columns] = cfg.dataset.getAnnotationsForTrial(cfg.trial_index);
        
        % Columns should be:
        %  Time, PX, PY, Fixation Mask, Saccade Mask
        % This script will first add:
        %  Stim#, ROI#, Overlap
        % Then clustering is performed
        
        for s = 1:length(cfg.stimuli)
            % Get stimulus/frame information
            stimulus_info = get_stimulus_info(cfg.project, cfg.stimuli(s).name);
            if(~isstruct(stimulus_info)), continue; end;

            frame = cfg.stimuli(s).frame;            
            if(frame == 0), continue; end;
            
            % Load regions of interest
            region_filename = cfg.project.getLatestROIFilename(stimulus_info);
            regions = VideoROIRegions(stimulus_info);
            
            if(isempty(region_filename))
                disp(['Warning: No ROIs defined for stimulus ' stimulus_info.name]);
                break;
            end
            
            regions.loadRegionsFromFile(region_filename);
            
            % Get ROI data
            [frameROIState, frameROIPosition, frameSceneChange] = regions.getFrameInfo(frame);
            
            
            
            %samples(:, 2) -> px
            %samples(:, 3) -> py
            % 4 -> fixation mask
            % 5 -> saccade mask
            % Add 
            
            
        end;        
    end


    function perform_analysis(cfg)
    % PERFORM_ANALYSIS  Perform analysis for all datasets and all trials.

        % Open project
        project = VideoROIProject(cfg.projectDirectory);
        
        % Open output file and write header
        outputFile = fopen(cfg.outputFile, 'w');        
        fwrite(outputFile, '"dataset", "stimulus", "roi_name", "roi", "t_fix_start", "t_fix_stop", "fix_duration"\n');       
                        
        numDatasets = project.getNumberOfDatasets();        
        
        % Loop over datasets and trials
        for d = 1:numDatasets
            dataset_info = project.getInfoForDataset(d);
            dataset = VideoROIDataset(dataset_info, 'Task4Logic');
            
            for t = 1:dataset.getNumberOfTrials();
                stimuli = dataset.getStimuliForTrial(t);

                cfg = struct();
                cfg.trial_index = t;
                cfg.project = project;
                cfg.outputFile = outputFile;                
                cfg.dataset = dataset;
                cfg.stimuli = stimuli;
                
                perform_analysis_trial(cfg)
            end
        end
        
        % Close output
        fclose(outputFile);
    end


    % Add default values to configuration structure
    if nargin < 1, cfg = struct; end;
    cfg = fill_defaults(cfg);
    
    % Then perform analysis
    perform_analysis(cfg);
end