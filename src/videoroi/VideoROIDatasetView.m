
classdef VideoROIDatasetView < EventProvider
  %
  %
  %
  %  *--------------------* *------*
  %  |                    | | Re   |
  %  |    Composite       | | gi   |
  %  |    Image + ROIs    | | on   | << Not sure about this
  %  |                    | | s    | Maybe add some options
  %  |                    | |      | and/or analysis tools
  %  *--------------------* *------*
  %
  %  *------------------------------*
  %  |                              |
  %  | Eye trace                    |
  %  |                              |
  %  *------------------------------*
  %
  %  Time control:
  %  *-------------------------*
  %  | Frames/stimuli          | Play
  %  *-------------------------*-----*
  %  | Trials                        |
  %  *-------------------------------*
  %
  % All data for the entire trial will be loaded, but the
  % XLimits will only contain 500ms.
  % The image will show the frame corresponding to the first
  % sample shown in the eye-trace.
  %
  % It should be possible to scroll to the last sample! That
  % means almost the entire trace window will be blank.
  %
  % The slider will jump to the first sample of the frame.
  %
  %
  
  methods(Access = public)
    function obj = VideoROIDatasetView()
      obj.screenResolution = [1024 768];
      obj.setupGui();
    end
    
    
    %
    % Sets resolution of screen.
    %
    function setResolution(obj, screenResolution)
      obj.screenResolution = screenResolution;
      
      I = ones(obj.screenResolution(1), obj.screenResolution(2), 3);
      set(obj.screenImage, 'CData', I);
      set(obj.screenImage, 'XData', [1 obj.screenResolution(2)]);
      set(obj.screenImage, 'XData', [1 obj.screenResolution(1)]);
    end
    
    
    function setPlayingState(obj, playing)
      if(playing)
        obj.playPauseButton.setLabel('Pause');
      else
        obj.playPauseButton.setLabel('Play');
      end;
    end
    
    
    function setCurrentTime(obj, currentTime)
      currentTime = currentTime - obj.offsetTime;
      
      if currentTime ~= obj.currentTime
        obj.currentTime = currentTime;
        obj.timeSlider.setValue(obj.currentTime);
        obj.onTimeSliderChanged(obj.timeSlider);
      end
    end

    
    %
    % Set total time.
    %
    function setTotalTime(obj, totalTime)
      obj.totalTime = totalTime;
      
      if obj.currentTime > obj.totalTime
        obj.timeSlider.setValue(obj.totalTime);
      end
      
      obj.timeSlider.setBounds(0, obj.totalTime);
      obj.updateLabels();
    end
    
    
    %
    % Sets the number of the trial currently displayed.
    %
    function setCurrentTrial(obj, currentTrial)
      if obj.currentTrial ~= currentTrial
        obj.currentTrial = currentTrial;
        
        if obj.trialSlider.getValue() ~= currentTrial
          obj.trialSlider.setValue(currentTrial)
        end
      end
      
      obj.updateLabels();
    end
    
    
    %
    % Set the total number of available trials.
    %
    function setNumberOfTrials(obj, numberOfTrials)
      obj.numberOfTrials = numberOfTrials;
      obj.trialSlider.setBounds(1, obj.numberOfTrials);
      obj.updateLabels();
    end
    
    
    function updateTrace(obj, time, position, mask)
      h = obj.traceAxes.getHandle();
      
      child = get(h, 'Children');
      for i = 1:numel(child)
        delete(child(i));
      end

      if numel(time) < 1, return; end;
      
      obj.offsetTime = time(1);
      time = time - obj.offsetTime;
      plot(h, time * 1e3, position(:, 1), 'b');
      plot(h, time * 1e3, position(:, 2), 'r');
      
      mask = logical(mask);
      plot(h, time(mask) * 1e3, position(mask, 1), 'b.');
      plot(h, time(mask) * 1e3, position(mask, 2), 'r.');
    end
    
    
    function updateScreen(obj, stimuli, gaze)
      h = obj.screenAxes.getHandle();
      
      child = get(h, 'Children');
      for i = 1:numel(child)
        delete(child(i));
      end
      
      hold(h, 'on');
      for i = 1:numel(stimuli)
        X = linspace(stimuli(i).position(1), stimuli(i).position(1) + stimuli(i).position(3) - 1, size(stimuli(i).data, 1));
        Y = linspace(stimuli(i).position(2), stimuli(i).position(2) + stimuli(i).position(4) - 1, size(stimuli(i).data, 2));
        image(X, Y, stimuli(i).data, 'Parent', h);
      end
      
      for i = 1:numel(stimuli)
        for j = 1:size(stimuli(i).positions, 1)
          position = squeeze(stimuli(i).positions(j, 1, :));
          
          line(position(1) + [0 0] * position(3), position(2) + [0 1] * position(4), 'Parent', h);
          line(position(1) + [1 1] * position(3), position(2) + [0 1] * position(4), 'Parent', h);
          
          line(position(1) + [0 1] * position(3), position(2) + [0 0] * position(4), 'Parent', h);
          line(position(1) + [0 1] * position(3), position(2) + [1 1] * position(4), 'Parent', h);
        end
      end
      
      plot(gaze(gaze(:, 4) == 1, 2), gaze(gaze(:, 4) == 1, 3), 'rx', 'Parent', h);
      plot(gaze(gaze(:, 5) == 1, 2), gaze(gaze(:, 5) == 1, 3), 'g.', 'Parent', h);
    end
  end
  
  properties(Access = private)
    datasetName = 'Unknown';
    
    % Represents the virtual screen (i.e. what the participant saw)
    screenResolution = [];
    screenAxes = [];
    screenImage = [];
    
    % Used to draw eye trace
    traceAxes = [];
    
    % Trial counts
    currentTrial = NaN;
    numberOfTrials = 1;
    
    % Time info
    offsetTime = 0;
    currentTime = NaN;
    totalTime = NaN;
    
    % Scrollbar used to control time and trial
    trialSlider = [];
    timeSlider = [];
    timeLabel = [];
    
    % Starting an stopping of playback
    playPauseButton = [];
  end
  
  methods(Access = private)
    %
    %
    %
    function setupGui(obj)
      obj.screenAxes = GUIAxes();
      obj.screenAxes.setMargin([0 0 0 0]);
      obj.screenAxes.setPadding([0 0 0 0]);
      obj.screenAxes.addEventListener('construction', @(src) obj.onScreenAxesCreated(src));
      
      obj.traceAxes = GUIAxes();
      obj.traceAxes.setMargin([0 0 0 0]);
      obj.traceAxes.addEventListener('construction', @(src) obj.onTraceAxesCreated(src));
      
      % Time control components
      obj.timeSlider = GUISlider();   % FIXME: Frames or seconds?!
      obj.timeSlider.addEventListener('change', @(x) obj.onTimeSliderChanged(x));
      obj.timeSlider.setStepSize(0.25, 0.5);
      
      obj.trialSlider = GUISlider();
      obj.trialSlider.addEventListener('change', @(src) obj.onTrialSliderChanged(src));
      obj.trialSlider.setStepSize(1.0, 5.0);
      
      obj.playPauseButton = GUIButton();
      obj.playPauseButton.addEventListener('click', @(src) obj.onPlayPauseButtonClicked(src));
      obj.playPauseButton.setLabel('Play');
      
      controlbar = GUIBoxArray();
      controlbar.setMargin([0 0 0 0]);
      controlbar.setHorizontalDistribution([NaN 25]);
      controlbar.addComponent(obj.trialSlider);
      controlbar.addComponent(obj.playPauseButton);
      
      obj.timeLabel = GUILabel('Time {} of {}sec / Trial {} of {}');
      
      horizontalSplit = GUIBoxArray();
      horizontalSplit.setHorizontalDistribution([NaN]);
      horizontalSplit.setMargin([0 0 0 0]);
      horizontalSplit.addComponent(obj.screenAxes);
      %horizontalSplit.addComponent(GUILabel('Placeholder'));
      
      % Put all components together
      verticalSplit = GUIBoxArray();
      verticalSplit.setVerticalDistribution([NaN 200 25 25 25]);
      verticalSplit.addComponent(horizontalSplit);
      verticalSplit.addComponent(obj.traceAxes);
      verticalSplit.addComponent(obj.timeSlider);
      verticalSplit.addComponent(controlbar);
      verticalSplit.addComponent(obj.timeLabel);
      
      mainWindow = GUIWindow();
      mainWindow.setTitle( sprintf('Dataset: %s', obj.datasetName) );
      
      mainWindow.addEventListener('keyPress', @(src, event) obj.onKeyPress(src, event));
      mainWindow.addEventListener('close', @(src) obj.onClose(src));
      mainWindow.addComponent(verticalSplit);
    end
    
    
    %
    % Update labels
    %
    function updateLabels(obj)
      obj.timeLabel.setLabel(sprintf( ...
        'Time %.2f of %.2f sec / Trial %d of %d', ...
        obj.currentTime, obj.totalTime, obj.currentTrial, obj.numberOfTrials));
    end
    
    
    %
    % Create a new image to show in the screen axes.
    %
    function onScreenAxesCreated(obj, src)
      h = src.getHandle();
      
      I = ones(obj.screenResolution(1), obj.screenResolution(2), 3);
      obj.screenImage = image(I, 'Parent', h);
      
      xlim(h, [0.5 obj.screenResolution(1) + 0.5]);
      ylim(h, [0.5 obj.screenResolution(2) + 0.5]);
      axis(h, 'equal');
      
      set(h, 'XTick', []);
      set(h, 'YTick', []);
    end
    
    
    %
    % Setup trace axes.
    %
    function onTraceAxesCreated(~, src)
      h = src.getHandle();
      
      xlim(h, [0 500]);
      hold(h, 'on');
      
      xlabel(h, 'Time (ms)');
      ylabel(h, 'Position (pixels)');
    end
    
    
    function onTrialSliderChanged(obj, src)
      value = round(src.getValue());
      obj.invokeEventListeners('changeTrial', value);
    end
    
    
    function onTimeSliderChanged(obj, src)
      value = src.getValue();
      obj.currentTime = value;
      obj.updateLabels();
      
      h = obj.traceAxes.getHandle();
      xlim(h, 1e3 * value + [0 500]);
      ylim(h, [0 1024]);
      
      obj.invokeEventListeners('changeTime', obj.offsetTime + value);
    end
    
    
    function onPlayPauseButtonClicked(obj, ~)
      obj.invokeEventListeners('playPauseVideo');
    end
    
    
    function onKeyPress(obj, ~, event)
      if(strcmp(event.Key, 'leftarrow'))
        newValue = obj.timeSlider.getValue() - 1/30;
        if newValue > 0
          obj.timeSlider.setValue(newValue);          
          obj.onTimeSliderChanged(obj.timeSlider);
        end
      end
      
      if(strcmp(event.Key, 'rightarrow'))
        newValue = obj.timeSlider.getValue() + 1/30;
        
        if newValue <= obj.totalTime
          obj.timeSlider.setValue(newValue);
          obj.onTimeSliderChanged(obj.timeSlider);
        end;
      end
    end
    
    
    function onClose(~, ~)
    end
  end
end
