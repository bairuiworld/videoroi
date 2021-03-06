classdef VideoROIStimulusView < EventProvider
  
  properties(Access = private)
    % GUI Components
    mainWindow;
    
    playPauseButton;
    
    frameAxes;
    frameImage;
    frameSlider;
    frameLabel;
    
    frameRect = {};
    frameRectCallbackID = {};
    
    roiList;
    sceneCheckbox;
    
    dataList;
    stimulusList;
    
    % Whether overlap is allowed or not
    overlapState;
    
    % Current frame state
    frameIndex;
    frameROIState;
    frameROIPosition;
    
    % Menu containing available tasks
    taskMenu;
    
    % Toggle overlap menu item
    overlapMenuItem;
    
    % True if the latest changes have not been saved
    unsavedFlag;
    
    % ROI Colors for listbox ...
    roiListColors = { ...
      '#000000', ...
      '#990000', '#009900', '#000099', ...
      '#999999', ...
      '#FF0000', '#00FF00', '#0000FF', ...
      '#FF9900', '#FF0099', ...
      '#99FF00', '#00FF99', ...
      '#0099FF', '#9900FF', '#FF9999', ...
      '#FFFF00', '#FF00FF', ...
      '#00FFFF', ...
      };
    
    % ... and rectangles (will be computed later)
    roiRectColors = {};
    
    % Number of frames
    numberOfFrames;
    
    currentProjectPath = '';
  end
  
  methods(Access = public)
    
    %
    % Constructor for the VideoROIView
    %
    function obj = VideoROIStimulusView()
      obj.overlapState = 1;
      obj.copyRectFromListColors();
      obj.setupGUI();
      
      obj.frameSlider.setValue(1);
      obj.frameSlider.setBounds(1, 2);
      
      obj.setupMenu();
    end
    
    
    %
    % Change the total number of frames in the loaded stimulus, this
    % causes the current frame to be reset to 1.
    %
    % @param frames Number of frames in the stimulus
    %
    function setNumberOfFrames(obj, frames)
      obj.numberOfFrames = frames;
      obj.frameSlider.setValue(1);
      
      if(frames <= 1)
        obj.frameSlider.setBounds(0, 1);
      else
        obj.frameSlider.setBounds(1, frames);
      end;
      
      obj.setCurrentFrame(1);
    end
    
    
    %
    % Changes the currently displayed frame
    %
    % @param frame The frame that should be shown
    %
    function setCurrentFrame(obj, frame)
      obj.frameSlider.setValue(frame);
      obj.updateFrameLabel();
      
      obj.doFrameChange(frame);
    end
    
    
    %
    % Set flag that indicates whether the camera position
    % has changed
    %
    % @param value True if change, false otherwise
    %
    function setSceneChange(obj, value)
      obj.sceneCheckbox.setValue(value);
    end
    
    
    function setProjectDirectory(obj, projectDirectory)
      obj.currentProjectPath = projectDirectory;
    end
    
    
    %
    % Changes ROI information (state and position)
    %
    % @param states Whether or not the ROIs are enabled
    % @param positions The X/Y/W/H position of the rectangle
    %
    function setROIInformation(obj, states, positions)
      obj.frameROIState = states;
      obj.frameROIPosition = positions;
    end
    
    
    %
    % Update list with regions of interest
    %
    % @param labels Cell array containing ROI names
    % @param states Whether or not the ROIs are enabled
    %
    function updateROIList(obj, labels, states)
      obj.roiList.clear();
      
      for i = 1:length(labels)
        if(states(i) == 0)
          roiState = 'disabled';
        else
          roiState = 'enabled';
        end
        
        itemLabel = ['<html><b style="color:' ...
          obj.roiListColors{i} ...
          '">' labels{i} ' (' roiState ')' ...
          '</b></html>'];
        
        obj.roiList.addItem(itemLabel);
      end
    end
    
    
    %
    % Updates all ROI rectangles in the current frame
    %
    % @param states Whether or not the ROIs are enabled
    % @param positions The X/Y/W/H position of the rectangle
    %
    function updateROIRects(obj, states, positions)
      numROIs = size(states, 1);
      numRects = length(obj.frameRect);
      
      if(numRects < numROIs)
        for i = (numRects+1):numROIs
          obj.frameRect{i} = 0;
          obj.frameRectCallbackID{i} = 0;
        end
      elseif (numRects > numROIs)
        for i = (numROIs+1:numRects)
          if(obj.frameRect{i} ~= 0)
            delete(obj.frameRect{i});
          end
        end
        obj.frameRect(numROIs+1:numRects) = [];
        obj.frameRectCallbackID(numROIs+1:numRects) = [];
      end
      
      for i = 1:numROIs
        state = states(i);
        position = squeeze(positions(i, :, :));
        
        % If the ROI is disabled, delete the rectangle
        if(state == 0)
          if(obj.frameRect{i} ~= 0)
            delete(obj.frameRect{i});
            obj.frameRect{i} = 0;
          end
        end
        
        % If the ROI is enabled, make sure the rectangle exists
        %  and set its position...
        if(state == 1)
          if(obj.frameRect{i} == 0)
            obj.createROIRect(i, position);
          else
            removeNewPositionCallback(obj.frameRect{i}, obj.frameRectCallbackID{i});
            setConstrainedPosition(obj.frameRect{i}, position(:)');
            obj.frameRectCallbackID{i} = addNewPositionCallback(obj.frameRect{i}, @(x) obj.onRectMoved(i));
          end
        end
      end
    end
    
    
    %
    % Changes the image currently being shown
    %
    % @param img Matrix containing the image data
    %
    function swapImage(obj, img)
      h = get(obj.frameImage, 'Parent');
      
      oldXLim = get(h, 'XLim');
      oldYLim = get(h, 'YLim');
      
      % Change image
      set(obj.frameImage, 'XData', [1 size(img, 2)]);
      set(obj.frameImage, 'YData', [1 size(img, 1)]);
      set(obj.frameImage, 'CData', img);
      
      newXLim = [0.5 size(img, 2) + 0.5];
      newYLim = [0.5 size(img, 1) + 0.5];
      
      % Limits have changed, update 'em
      if( any(newXLim ~= oldXLim) || any(newYLim ~= oldYLim) )
        
        axis(h, 'equal');
        
        % Change limits on image
        set(h, 'Xlim', newXLim);
        set(h, 'Ylim', newYLim);
        
        % Update constraints on ROI rectangles
        numROIs = length(obj.frameRect);
        for i = 1:numROIs
          if(obj.frameRect{i} > 0)
            fcn = obj.makeConstraintFcn(i);
            setPositionConstraintFcn(obj.frameRect{i}, fcn);
          end
        end
      end
    end
    
    
    %
    % Display an error message
    %
    % @param message Message to display
    %
    function displayError(~, message)
      errordlg(message);
    end
    
    
    %
    % Sets playing state (true is playing, false is stopped).
    %
    function setPlayingState(obj, playing)
      if(playing)
        obj.playPauseButton.setLabel('Pause');
      else
        obj.playPauseButton.setLabel('Play');
      end;
    end
    
  end
  
  
  methods(Access = protected)
    
    %%%%%%%%%%%%%%%%%%%%%%
    % Graphical interace %
    %%%%%%%%%%%%%%%%%%%%%%
    
    
    function setupGUI(obj)
      % Left part shows the stimulus
      obj.frameAxes = GUIAxes();
      obj.frameAxes.addEventListener('construction', @(x) obj.onFrameAxesCreated(x));
      
      % Frame slider at the bottom
      obj.frameSlider = GUISlider();
      obj.frameSlider.addEventListener('change', @(x) obj.onFrameSliderChanged(x));
      
      obj.playPauseButton = GUIButton();
      obj.playPauseButton.addEventListener('click', @(src) obj.onPlayPauseButtonClicked(src));
      obj.playPauseButton.setLabel('Play');
      
      controlbar = GUIBoxArray();
      controlbar.setMargin([0 0 0 0]);
      controlbar.setHorizontalDistribution([NaN 25 25]);
      controlbar.addComponent(obj.frameSlider)
      controlbar.addComponent(obj.playPauseButton);
      
      obj.frameLabel = GUILabel('Frame ? of #');
      
      horizontalSplit = GUIBoxArray();
      horizontalSplit.setHorizontalDistribution([NaN 150]);
      horizontalSplit.addComponent(obj.frameAxes);
      horizontalSplit.addComponent(obj.setupStimulusPropertiesPane());
      
      % Put all components together
      verticalSplit = GUIBoxArray();
      verticalSplit.setVerticalDistribution([NaN 25 25]);
      verticalSplit.addComponent(horizontalSplit);
      verticalSplit.addComponent(obj.frameLabel);
      verticalSplit.addComponent(controlbar);
      
      obj.mainWindow = GUIWindow();
      obj.mainWindow.setTitle(sprintf('Stimulus: Unknown'));
      obj.mainWindow.addEventListener('keyPress', @(src, event) obj.onKeyPress(src, event));
      obj.mainWindow.addEventListener('close', @(src) obj.onClose(src));
      obj.mainWindow.addComponent(verticalSplit);
    end
    
    
    %
    % Creates the ROI list and associated management buttons
    %
    function verticalSplit = setupStimulusPropertiesPane(obj)
      obj.roiList = GUIList();
      
      verticalSplit = GUIBoxArray();
      verticalSplit.setVerticalDistribution([30 NaN 30 30]);
      
      verticalSplit.addComponent(GUILabel('Regions:'));
      verticalSplit.addComponent(obj.roiList);
      
      toggleButton = GUIButton();
      toggleButton.setLabel('Toggle ROI');
      toggleButton.addEventListener('click', @(src) obj.onToggleButtonClicked(src));
      
      %addButton = GUIButton();
      %addButton.setLabel('Add ROI');
      %addButton.addEventListener('click', @(src) obj.onAddButtonClicked(src));
      
      obj.sceneCheckbox = GUICheckbox();
      obj.sceneCheckbox.setLabel('Scene changed');
      obj.sceneCheckbox.addEventListener('click', @(src) obj.onSceneCheckboxClicked(src));
      
      verticalSplit.addComponent(toggleButton);
      %verticalSplit.addComponent(addButton);
      verticalSplit.addComponent(obj.sceneCheckbox);
    end
    
    
    %
    % Creates the file-menu
    %
    function setupMenu(obj)
      h = uimenu('Label', '&File');
      uimenu(h, 'Label', '&Import regions', 'Callback', @(src, x) obj.onImportROI(src));
      uimenu(h, 'Label', '&Export regions', 'Callback', @(src, x) obj.onExportROI(src));
            
      h = uimenu('Label', '&Region');
      uimenu(h, 'Label', '&Add region', 'Callback', @(src, x) obj.onAddButtonClicked(src));
      uimenu(h, 'Label', '&Save changes', 'Callback', @(src, x) obj.onSave(src));      
    end;
    
    
    
    %
    % Copy list colors into rectangle colors
    %
    function copyRectFromListColors(obj)
      for i = 1:length(obj.roiListColors)
        color = [ ...
          hex2dec(obj.roiListColors{i}(2:3)), ...
          hex2dec(obj.roiListColors{i}(4:5)), ...
          hex2dec(obj.roiListColors{i}(6:7))];
        
        obj.roiRectColors{i} = color/255;
      end
    end
    
    
    %
    % Returns constraint function
    %
    % @param Region of interest to create function for.
    %
    function fcn = makeConstraintFcn(obj, roi)
      
      % Share with returned function, when this changes, this
      % function should be called again.
      xlim = get(get(obj.frameImage, 'Parent'), 'XLim') + [0.5 -0.5];
      ylim = get(get(obj.frameImage, 'Parent'), 'YLim') + [0.5 -0.5];
      
      function cpos = overlapConstraintFcn(pos)
        
        xconstr = xlim;
        yconstr = ylim;
        
        % Update constraints based on other regions
        if obj.overlapState == 0
          original_pos = getPosition(obj.frameRect{roi});
          
          numROIs = length(obj.frameRect);
          for i = 1:numROIs
            if roi == i || obj.frameRect{i} == 0, continue; end;
            other_pos = getPosition(obj.frameRect{i});
            
            xoverlap = min( other_pos(1) + other_pos(3), pos(1) + pos(3) ) - max( other_pos(1), pos(1) );
            yoverlap = min( other_pos(2) + other_pos(4), pos(2) + pos(4) ) - max( other_pos(2), pos(2) );
            
            xleft = other_pos(1) + other_pos(3);
            ytop = other_pos(2) + other_pos(4);
            
            xright = other_pos(1);
            ybottom = other_pos(2);
            
            if yoverlap > 0
              if xleft >= xconstr(1) && xleft <= original_pos(1)
                xconstr(1) = xleft;
              end
              
              if xright <= xconstr(2) && xright >= (original_pos(1) + original_pos(3))
                xconstr(2) = xright;
              end
            end
            
            if xoverlap > 0
              if ytop >= yconstr(1) && ytop <= original_pos(2)
                yconstr(1) = ytop;
              end
              
              if ybottom <= yconstr(2) && ybottom >= (original_pos(2) + original_pos(4))
                yconstr(2) = ybottom;
              end
            end
          end
        end
        
        % Contrain position
        cpos(1) = min(max(pos(1), xconstr(1)), xconstr(2) - pos(3));
        cpos(2) = min(max(pos(2), yconstr(1)), yconstr(2) - pos(4));
        
        cpos(3:4) = pos(3: 4);
      end
      
      fcn = @overlapConstraintFcn;
    end
    
    
    %
    % Creates a new ROI rectangle
    %
    % @param i - Index of the ROI rectangle
    % @param position - Initial position of the rectangle
    %
    function createROIRect(obj, i, position)
      if(obj.frameRect{i} > 0)
        delete(obj.frameRect{i});
      end
      
      obj.frameRect{i} = imrect(get(obj.frameImage, 'Parent') , position(:)');
      
      xl = get(get(obj.frameImage, 'Parent'), 'XLim');
      yl = get(get(obj.frameImage, 'Parent'), 'YLim');
      
      fcn = obj.makeConstraintFcn(i);
      setPositionConstraintFcn(obj.frameRect{i}, fcn);
      
      setColor(obj.frameRect{i}, obj.roiRectColors{i});
      obj.frameRectCallbackID{i} = addNewPositionCallback(obj.frameRect{i}, @(x) obj.onRectMoved(i));
    end
    
    
    %
    % Internal function invoked when the current frame
    % has been changed. It will set an internal variable
    % and call methods waiting for the "frameChange" event.
    %
    % @param index The new frame index
    %
    function doFrameChange(obj, index)
      obj.frameIndex = index;
      obj.invokeEventListeners('frameChange', index);
      drawnow;
    end
    
    
    %
    % Update the label shown above the frame selection slider
    %
    function updateFrameLabel(obj)
      obj.frameLabel.setLabel(['Frame ' num2str(obj.frameSlider.getValue()) ...
        ' of ' num2str(obj.numberOfFrames)]);
    end
    
    
    % %%%%%%%%%%%%%% %
    % EVENT HANDLERS %
    % %%%%%%%%%%%%%% %
    
    
    %
    % Function called when the frame axes have been created
    % It initilizes a test-pattern an configures the axes
    %
    % @param src Newly created GUIAxes object
    %
    function onFrameAxesCreated(obj, src)
      h = src.getHandle();
      
      I = ones(1024, 768, 3);
      obj.frameImage = image(I, 'Parent', h);
      
      set(h, 'XTick', []);
      set(h, 'YTick', []);
    end
    
    
    %
    % Function called when the window is being closed
    %
    function onClose(obj, ~)
      if(obj.unsavedFlag)
        choice = questdlg('Save changes before loading stimulus?', ...
          'Save changed', 'Yes', 'No', 'Yes');
        
        if(strcmp(choice, 'Yes'))
          obj.invokeEventListeners('saveROIFile');
        end
      end
    end
    
    
    function onPlayPauseButtonClicked(obj, ~)
      obj.invokeEventListeners('playPauseVideo');
    end
    
    
    %
    % Function called when "save" has been selected. If save
    % the ROIs under a new file in the project directory.
    %
    function onSave(obj, ~)
      obj.invokeEventListeners('saveROIFile');
    end
    
    
    %
    % Function called when "import" has been selected. It shows
    % a file-selection dialog and will invoke a callback
    % once a valid file has been selected.
    %
    function onImportROI(obj, ~)
      [filename, pathname] = uigetfile({'*.roi', 'ROI Files'}, 'Import ROIs');
      
      if(filename ~= 0)
        filename = fullfile(pathname, filename);
        obj.invokeEventListeners('importROIFile', filename);
        obj.unsavedFlag = 1;
      end
    end
    
    
    %
    % Function called when "export" has been selected. It will show
    % a dialog and invoke a callback once a valid file-name has been
    % selected.
    %
    function onExportROI(obj, ~)
      [filename, pathname] = uiputfile({'*.roi', 'ROI Files'}, 'Save ROIs As');
      
      if(filename ~= 0)
        filename = fullfile(pathname, filename);
        obj.invokeEventListeners('exportROIFile', filename);
      end
    end
    
    
    %
    % Function called when the "toggle ROI" button has been clicked.
    % It will invoke a callback and pass the selected ROI as an
    % argument.
    %
    function onToggleButtonClicked(obj, ~)
      obj.invokeEventListeners('toggleROI', obj.roiList.getSelectedIndex());
      obj.unsavedFlag = 1;
    end
    
    
    %
    % Function called when the "add ROI" button has been clicked.
    % It will ask for the name of the new ROI and invoke a callback.
    %
    function onAddButtonClicked(obj, ~)
      roiName = inputdlg('Enter name for ROI:', 'Add new ROI', 1);
      
      if ~isempty(roiName)
        obj.invokeEventListeners('newROI', roiName{1}, obj.frameIndex);
        obj.unsavedFlag = 1;
      end
    end
    
    
    function onSceneCheckboxClicked(obj, ~)
      obj.invokeEventListeners('sceneChanged', obj.frameIndex, obj.sceneCheckbox.getValue());
      obj.unsavedFlag = 1;
    end


    function onKeyPress(obj, ~, event)
      if(strcmp(event.Key, 'leftarrow'))
        newValue = obj.frameSlider.getValue() - 1;
        
        if(newValue > 0)
          obj.frameSlider.setValue(newValue);
          obj.onFrameSliderChanged(obj.frameSlider);
        end
      end
      
      if(strcmp(event.Key, 'rightarrow'))
        newValue = obj.frameSlider.getValue() + 1;
        
        if(newValue <= obj.numberOfFrames)
          obj.frameSlider.setValue(newValue);
          obj.onFrameSliderChanged(obj.frameSlider);
        end;
      end
    end
    
    
    %
    % Function called when the frame slider has been moved.
    % It will compute the new frame index and notifies the
    % controller about it.
    %
    % @param src GUISlider instance
    %
    function onFrameSliderChanged(obj, src)
      frame = src.getValue();
      
      if ~isinteger(frame)
        frame = floor(src.getValue());
        if(frame < 1), frame = 1; end;
        src.setValue(frame);
      end
      
      obj.updateFrameLabel();
      obj.doFrameChange(frame);
    end
    
    
    function onRectMoved(obj, roi)
      position = getPosition(obj.frameRect{roi});
      obj.invokeEventListeners('moveROI', roi, position);
      obj.unsavedFlag = 1;
    end
    
  end
end
