classdef MotionCorrection < nansen.stack.ImageStackProcessor
%nansen.processing.MotionCorrection Run motion correction on ImageStacks
%
%   This class is an abstract class that provides a framework for running
%   motion correction on ImageStack objects. It inherits the following 
%   classes:
%
%   - nansen.DataMethod : Provides data I/O model and options functionality
%   - nansen.stack.ImageStackProcessor : Process ImageStack in subparts
%
%   Known subclasses:
%   - nansen.wrappers.normcorre.Processor : Implements the normcorre toolbox
%   - nansen.wrappers.flowreg.Processor : Implements the flowregistration toolbox
%
%  obj = obj@nansen.processing.MotionCorrection(dataLocation) creates the
%  object based on a given dataLocation. The dataLocation can be:
%       1) A filepath
%       2) An ImageStack (containing VirtualData)
%       3) A struct-based DataLocation (not implemented yet).
%
%  obj = obj@nansen.processing.MotionCorrection(dataLocation, options)
%  creates the object and specifies the options to use for processing.
%
% Notes:
%
%   This class creates the following data variables:
%
%     * <strong>FovAverageProjection</strong> : Average projection from the full corrected stack
%
%     * <strong>FovMaximumProjection</strong> : Maximum projection from the full corrected stack
%
%     * <strong>MotionCorrectionStats</strong> : A struct array with various stats from motion correction.
%           - offsetX : Rigid frame offset in x (numFrames x 1)
%           - offsetY : Rigid frame offset in y (numFrames x 1)
%           - rmsMovement : root mean square movement for frames (numFrames x 1)
%
%     * <strong>MotionCorrectionReferenceImage</strong> : A stack of reference images 
%     (templates) for motion correction. One reference per chunk
%       
%     * <strong>MotionCorrectionTemplates8bit</strong> : Same as above cast to 8bit
%
%     * <strong>MotionCorrectedAverageProjections</strong> : Image stack with average
%     projections. Each average projection is from one chunk of the stack
%
%     * <strong>MotionCorrectedAverageProjections8bit</strong> : Same as above, cast to 8bit
%     
%     * <strong>MotionCorrectedMaximumProjections</strong> : Image stack with maximum
%     projections. Each maximum projection is from one chunk of the stack
%
%     * <strong>MotionCorrectedMaximumProjections8bit</strong> : Same as above, cast to 8bit


%   QUESTIONS:
%       b) How to resolve initializing this method with a different set of
%          options than before?
%       
%       - Should convertion of projection stacks and saving of fov images
%         be part of this class or should they be different methods?



    % Todo: 
    %   [ ] Save general options for motion correction... 
    %
    %   [v] Multichannel support
    %
    %   [ ] Move preview method to stack.ChunkProcessor (and rename to testrun/samplerun etc)
    %   [v] Move preview functionality to ImageStackProcessor...
    %
    %   [ ] Move saveTiffStack & openTiffStack to somewhere else (not sure where.)
    %
    %   [ ] Add correctLineOffset, shiftStackSubRes functions
    %
    %   [ ] Save shifts in standardized output as well as method outputs...
    %
    %   POSTPROCESSING
    %   
    %   [ ] Use min max when recasting a galvo scan. Less noise, so the
    %       upper percentile value saturates a lot of signal...
    %   
    %   [ ] Save temporal downsampled stacks (postprocessing?).
    %           - Save successively, if downsampling
    %           - No: Should be a separate method
    %
    %   [ ] Save 25th prctile (or better approximation to baseline) stack 
    %
    %   [ ] Need to load image stats. Also, nice to update imagestats if
    %       they are not available...
    %   [ ] Save projection images for raw stacks.
    %   [ ] Save other metrics to assess registration quality

    
    properties (Abstract, Constant)
        ImviewerPluginName
    end

    properties (Dependent, SetAccess = private)
        RecastOutput        % Flag for whether to recast output.
    end
    
    properties
        ImageStatsProcessor
    end
    
    properties (Access = protected) % Data to keep during processing.
        ToolboxOptions      % Options for specific toolbox that is used for image registration
        ImageStats          % Array of imagestats...
        ShiftsArray         % Array of detected shifts for each frame
        CorrectionStats     % Array of stats related to corrcetion results.
        
        CurrentRefImage     % Current reference image
        ReferenceStack      % Stack for reference (template) images
        AvgProjectionStack  % Stack for average projection images for each subpart
        MaxProjectionStack  % Stack for maximum projection images for each subpart
    end
    
    
    methods (Abstract, Access = protected) % Abstract methods that subclasses must implement
        
        S = getToolboxSpecificOptions(obj, varargin) % -> toolboxwrapper
                
        initializeShifts(obj, numFrames) % Protected?
        
        updateCorrectionStats(obj, S, shiftsArray, frameIndices)
        
        addDriftToShifts        % Subclasses use different definitions for shifts, so this need to be an abstract method. Todo: always use struct arrays for shifts?
        
        saveShifts(obj, shiftsArray)
        
        ref = initializeTemplate(obj, Y, opts); % Todo: Rename to create template...
        
        M = registerImageData(obj, Y) % Run motion correction on subpart of ImageStack
        
    end
    
    methods (Static, Abstract) % Abstract methods that subclasses must implement
         shifts = addShifts(shifts, offset)
    end
    
    methods % Structors
        
        function obj = MotionCorrection(varargin)
        %MotionCorrection Constructor for MotionCorrection superclass
            obj@nansen.stack.ImageStackProcessor(varargin{:})
        end
        
        function delete(obj)
            
            if ~isempty(obj.ReferenceStack)
                delete(obj.ReferenceStack)
            end
            
            if ~isempty(obj.AvgProjectionStack)
                delete(obj.AvgProjectionStack)
            end
            
            if ~isempty(obj.MaxProjectionStack)
                delete(obj.MaxProjectionStack)
            end
        end
        
    end
    
    methods 
        function recastOutput = get.RecastOutput(obj)
        %RecastOutput Determine if output needs to be recast.    
            dataTypeIn = obj.SourceStack.DataType;
            dataTypeOut = obj.Options.Export.OutputDataType;
            recastOutput = ~strcmp(dataTypeIn, dataTypeOut);
        end
    end
    
    methods (Access = protected) % Overide ImageStackProcessor methods
                
        function runPreInitialization(obj)
        %onPreInitialization Method that runs before the initialization step    
            
            % Determine how many steps are required for the method
            runPreInitialization@nansen.stack.ImageStackProcessor(obj)
            
            % 1) Check if stack should be recast before saving.
            if obj.RecastOutput
                % Need to compute pixel statistics for source stack..
                obj.addStep('pixelstats', 'Compute pixel statistics', 'beginning')
            end
            
        end
        
        function onInitialization(obj)
            
            % Store basic info about the raw image stack in local variables
            stackSize = size(obj.SourceStack.Data);
            obj.validateStackSize(stackSize)

            % Get options (preconfigs) for the normcorre registration
            % Todo: Different toolboxes might require different inputs.
            obj.ToolboxOptions = obj.getToolboxSpecificOptions(stackSize);
           
            % Todo: Validate options. I.e, if processor is run again, some
            % of the options should be the same... 
           
            if obj.RecastOutput % Calculate imagestats if needed (for recasting).
                obj.displayStartStep('pixelstats')
                
                processor = stack.methods.computeImageStats(obj.SourceStack, ...
                    'DataIoModel', obj.DataIoModel);
                processor.IsSubProcess = true;
                processor.runMethod()
                
                obj.displayFinishStep('pixelstats')
            else
                % Can be computed during motion correction
                obj.ImageStatsProcessor = stack.methods.computeImageStats(...
                    obj.SourceStack, 'DataIoModel', obj.DataIoModel);
                obj.ImageStatsProcessor.IsSubProcess = true;
                obj.ImageStatsProcessor.matchConfiguration(obj)
            end

            numFrames = stackSize(end); % Todo...
            dataTypeIn = obj.SourceStack.DataType;
            dimensionArrangement = obj.SourceStack.Data.StackDimensionArrangement;

            % Open output file
            dataTypeOut = obj.Options.Export.OutputDataType;
            obj.openTargetStack(stackSize, dataTypeOut, dimensionArrangement);
            
            obj.ImageStats = obj.getImageStats(numFrames); % Todo: Remove???
            
            % Initialize (or load) results
            obj.initializeShifts(numFrames);
            obj.initializeCorrectionStats(numFrames);

            % Create image stack for saving reference (template) images
            varName = 'MotionCorrectionReferenceImage'; %'MotionCorrectionTemplate'
            
            refArraySize = [stackSize(1:end-1), obj.NumParts];
            refArray = zeros(refArraySize, dataTypeIn);
            obj.ReferenceStack = obj.openTiffStack(varName, refArray);
            
            % Todo implement like this instead of above:
            %obj.saveData(refName, refArray)
            %obj.ReferenceStack = obj.loadData(refName)
            
            % Create image stack for saving average projection images
            if obj.Options.Export.saveAverageProjection
                varName = 'MotionCorrectedAverageProjections';
                obj.AvgProjectionStack = obj.openTiffStack(varName, refArray);
            end
                
            % Create image stack for saving maximum projection images
            if obj.Options.Export.saveMaximumProjection
                varName = 'MotionCorrectedMaximumProjections';
                obj.MaxProjectionStack = obj.openTiffStack(varName, refArray);
            end

            
            if ~strcmp(dataTypeIn, 'uint8')
                refArray = zeros(refArraySize, 'uint8');
                fovArray = zeros(refArraySize(1:end-1), 'uint8');
                varName = 'MotionCorrectionTemplates8bit';
                
                obj.DerivedStacks.Templates8bit = ...
                    obj.openTiffStack(varName, refArray);
                
                if obj.Options.Export.saveAverageProjection
                    varName = 'MotionCorrectedAverageProjections8bit';
                    obj.DerivedStacks.AvgProj8bit = ...
                        obj.openTiffStack(varName, refArray);
                    obj.DerivedStacks.AvgFovImage = ...
                        obj.openTiffStack('FovAverageProjection', fovArray, 'fov_images', false);
                end
                
                if obj.Options.Export.saveMaximumProjection
                    varName = 'MotionCorrectedMaximumProjections8bit';
                    obj.DerivedStacks.MaxProj8bit = ...
                        obj.openTiffStack(varName, refArray);
                    obj.DerivedStacks.MaxFovImage = ...
                        obj.openTiffStack('FovMaximumProjection', fovArray, 'fov_images', false);
                end
            end
        end
        
        function onCurrentChannelSet(obj, currentChannel)
            onCurrentChannelSet@nansen.stack.ImageStackProcessor(obj, currentChannel)
                            
            obj.ReferenceStack.CurrentChannel = currentChannel;

            if ~isempty(obj.AvgProjectionStack)
                obj.AvgProjectionStack.CurrentChannel = currentChannel;
            end
            
            if ~isempty(obj.MaxProjectionStack)
                obj.MaxProjectionStack.CurrentChannel = currentChannel;
            end
        end
        
        function onCurrentPlaneSet(obj, currentPlane)
            onCurrentPlaneSet@nansen.stack.ImageStackProcessor(obj, currentPlane)
                            
            obj.ReferenceStack.CurrentPlane = currentPlane;

            if ~isempty(obj.AvgProjectionStack)
                obj.AvgProjectionStack.CurrentPlane = currentPlane;
            end
            
            if ~isempty(obj.MaxProjectionStack)
                obj.MaxProjectionStack.CurrentPlane = currentPlane;
            end
        end

        function [Y, summary] = processPart(obj, Y, ~)
            
             Y = obj.preprocessImageData(Y);
            
             [Y, summary] = obj.registerImageData(Y);
             
             Y = obj.postprocessImageData(Y);

        end
        
        function onCompletion(obj)
            
            % Todo: Rename to completeCurrentChannelCurrentPlane

            i = 1;
            j = obj.CurrentPlane;
            
            % Determine amount of cropping to use for adjusting image data
            % to uint8
            maxX = max(abs(obj.CorrectionStats{i, j}.offsetX));
            maxY = max(abs(obj.CorrectionStats{i, j}.offsetY));
            crop = round( max([maxX, maxY])*1.5 );
            
            % Save reference images to 8bit
            imArray = obj.ReferenceStack.getFrameSet(1:obj.NumParts);
            imArray = stack.makeuint8(imArray);
            obj.saveTiffStack('MotionCorrectionTemplates8bit', imArray)
            
            
            % Save average and maximum projections as 8-bit stacks.
            if obj.Options.Export.saveAverageProjection
                obj.saveProjectionImages('average', crop)
            end
            
            if obj.Options.Export.saveMaximumProjection
                obj.saveProjectionImages('maximum', crop)
            end
            
            if obj.SourceStack.NumChannels > 1 && ...
                    ismember(obj.SourceStack.NumChannels, obj.CurrentChannel)
                if obj.CurrentPlane == obj.SourceStack.NumPlanes
                    obj.resaveRGBProjectionImages('average')
                    obj.resaveRGBProjectionImages('maximum')
                end
            end
        end
        
        function S = repeatStructPerDimension(obj, S)
        %repeatStructPerDimension Repeat a struct of result per dimension
        %
        %   For stack with multiple channels or planes, the input struct is
        %   repeated for the length of each of those dimensions
        %
        %   Differs from superclass in that results are not saved per
        %   channel (correction is the same for each channel).
        
            numChannels = 1;
            numPlanes = obj.SourceStack.NumPlanes;
            S = repmat({S}, numChannels, numPlanes);
        end
        
    end
        
    methods (Access = protected) % Pre- and processing methods for imagedata

        function Y = preprocessImageData(obj, Y, ~, ~)
        %preprocessImageData Preprocess image data before registration
        %
        %   Take care of some preprocessing steps that should be common for
        %   many motion correction methods.
        
            % Update image stats
            % Todo: Only do this if output should be recast?
            % Todo: Do this using the stack.methods.computeImageStats class
            
            if ~isempty( obj.ImageStatsProcessor )
                obj.ImageStatsProcessor.setCurrentPart(obj.CurrentPart);
                % Todo: set channel and plane
                obj.ImageStatsProcessor.processPart(Y)
            end
            
            i = 1;
            j = obj.CurrentPlane;
            
            % Subtract minimum value. Might not be necessary...
            minVal = prctile(obj.ImageStats{i,j}.prctileL2, 5);
            Y = Y - minVal;

            Y = single(Y); % Cast to single for the alignment

            % Todo: Should this be here or baked into the
            % getRawStack / getframes method of rawstack?
            
            % Todo, implement options selection
            [Y, bidirBatchSize, colShifts] = nansen.wrapper.normcorre.utility.correctLineOffsets(Y, 100);
            
            
            %frameInd = obj.CurrentFrameIndices;
                        
            % Get template for motion correction of current part
            if obj.CurrentPart == 1
                
                ref = obj.ReferenceStack.getFrameSet(1);
                
                if all(ref(:)==0)
                    ref = obj.initializeTemplate(Y); %<- todo: save initial template to session
                end
                
                % Assign current reference image
                obj.CurrentRefImage = ref;
                
                % Save reference image
                refOut = cast(ref, obj.SourceStack.DataType);
                obj.ReferenceStack.writeFrameSet(refOut, obj.CurrentPart);
                
            elseif isempty(obj.CurrentRefImage)
                ref = obj.ReferenceStack.getFrameSet( obj.CurrentPart - 1);
                obj.CurrentRefImage = single(ref);
            end

        end

        function M = postprocessImageData(obj, Y, ~, ~)
            
            iIndices = obj.CurrentFrameIndices;
            iPart = obj.CurrentPart;
            
            i = 1;
            j = obj.CurrentPlane;
            
            % Add minval... % Todo: Check if this step is necessary...
            minVal = prctile(obj.ImageStats{i,j}.prctileL2, 5);
            Y = Y + minVal;

            % Correct drift.
            obj.Options.General.correctDrift = true;
            if iPart ~= 1 && obj.Options.General.correctDrift
                
                % Todo: Make sure this does not leave black edges!
                [Y, drift] = obj.correctDrift(Y);
                
                % Todo:
                updateReference = false;
                if updateReference                    
                    obj.CurrentRefImage = imtranslate( obj.CurrentRefImage, [drift(1), drift(2)] );
                    % Write reference image to file.
                    templateOut = cast(obj.CurrentRefImage, obj.SourceStack.DataType);
                    obj.ReferenceStack.writeFrameSet(obj.CurrentRefImage, obj.CurrentPart)
                end
                
                % Add drift to shifts. %Todo: Flowreg
                obj.addDriftToShifts(drift)
                obj.ShiftsArray{i,j}(iIndices) = obj.addShifts(...
                    obj.ShiftsArray{i,j}(iIndices), drift);
            end

            % Save stats based on motion correction shifts
            obj.updateCorrectionStats(iIndices)

            % Check if output should be recast...
            dataTypeIn = obj.SourceStack.DataType;
            dataTypeOut = obj.Options.Export.OutputDataType;
            
            recastOutput = ~strcmp(dataTypeIn, dataTypeOut);
            
            % Save images to corrected stack (todo: place in method?)
            if recastOutput
                % Todo: throw out outliers instead of using prctile?
                minVal = prctile(obj.ImageStats{i,j}.prctileL2, 5);
                %maxVal = max(obj.ImageStats{i,j}.prctileU2);
                maxVal = max(obj.ImageStats{i,j}.maximumValue);

                switch dataTypeOut
                    case 'uint8'
                        M = stack.makeuint8(Y, [minVal, maxVal]);
                    otherwise
                        error('Not implemented yet')
                end
            else
                M = cast(Y, dataTypeIn);
            end
            
            % Save projections images if selected
            
            % Todo: This shold be done after data is written to target
            % stack...
            
            if obj.Options.Export.saveAverageProjection
                dim = ndims(Y);
                avgProj = mean(Y, dim);
                avgProj = cast(avgProj, dataTypeIn);
                obj.AvgProjectionStack.writeFrameSet(avgProj, iPart)
            end
            
            if obj.Options.Export.saveMaximumProjection
                % Filter using okada before getting the max.
                dim = ndims(Y);
                
                % Todo: Adjust binsize according to framerate and/or
                % indicator type.
                Y_ = movmean(Y, 3, dim);
                maxProj = max(Y_, [], dim);
                maxProj = cast(maxProj, dataTypeIn);
                obj.MaxProjectionStack.writeFrameSet(maxProj, iPart)
            end
            
            % Important: Do this last, because shifts are used to check if 
            % current part is corrected or not.
            obj.saveShifts()
        end
        
    end

    methods (Access = protected)
           
        function openTargetStack(obj, stackSize, dataType, ~)

            % Get file reference for corrected stack
            DATANAME = 'TwoPhotonSeries_Corrected';
            filePath = obj.getDataFilePath( DATANAME );
            
            % Call method of ImageStackProcessor
            openTargetStack@nansen.stack.ImageStackProcessor(obj, filePath, ...
                stackSize, dataType, 'DataDimensionArrangement', ...
                obj.SourceStack.Data.StackDimensionArrangement)
            
            % Inherit metadata from the source stack
            obj.TargetStack.MetaData.updateFromSource(obj.SourceStack.MetaData)
            
            % Make sure caching is turned off...
            obj.TargetStack.Data.UseDynamicCache = false;

        end
        
        function opts = initializeOptions(obj, opts, optionsVarname)
        % Get filepath for saving options file to session folder

            filePath = obj.getDataFilePath(optionsVarname, '-w', ...
                'Subfolder', 'motion_corrected', 'IsInternal', true);
            
            % And check whether it already exists on file...
            if isfile(filePath)
                optsOld = obj.loadData(optionsVarname);
                
                % Todo: make this conditional, e.g if redoing aligning, we
                % want to overwrite options...
                
                % If correction is resumed with different options
                if ~isequal(opts, optsOld)
                    warnMsg = ['options already exist for ', ...
                      'this session, but they are different from the ', ...
                      'current options. Existing options will be used.'];
                    warning('%s %s', warnMsg,  class(obj) )
                    opts = optsOld;
                end
                
            else % Save to file if it does not already exist
                % Save options to session folder
                obj.saveData(optionsVarname, opts, ...
                    'Subfolder', 'motion_corrected')
            end
            
        end
                 
    end
    
    methods (Access = private)
        
        function saveProjectionImages(obj, projectionType, cropAmount)
        %saveProjectionStack Save projections for current channel/plane
        %
        %   Save an 8bit version of the projection stack
        %   Save a full projection image based on the projection stack
        
            if numel(obj.CurrentChannel) > 1
                lastDim = 4;
            else
                lastDim = 3;
            end
        
            switch lower( projectionType )
                case 'average'
                    sourceStackName = 'AvgProjectionStack';
                    targetStackNameA = 'AvgProj8bit';
                    targetStackNameB = 'AvgFovImage';
                    getFullProjection = @(IM) mean(IM, lastDim);
                case 'maximum'
                    sourceStackName = 'MaxProjectionStack';
                    targetStackNameA = 'MaxProj8bit';
                    targetStackNameB = 'MaxFovImage';
                    getFullProjection = @(IM) max(IM, [], lastDim);
            end
            
            % Save an 8bit version of the projection stack
            imArray = obj.(sourceStackName).getFrameSet(1:obj.NumParts);
            imArray = squeeze(imArray); %Squeeze singleton dims (C or Z)
            %imArray8b = stack.makeuint8(imArray_, [], [], cropAmount);      % todo: Generalize this function / add tolerance as input
            imArray8b = obj.adjustColorPerChannel(imArray, cropAmount);
            obj.DerivedStacks.(targetStackNameA).writeFrameSet(imArray8b, 1:obj.NumParts)

            % Save projection of the projection stack
            fovProjection = getFullProjection(imArray);
            %fovProjection = stack.makeuint8(fovProjection, [], [], cropAmount);
            fovProjection = obj.adjustColorPerChannel(fovProjection, cropAmount);

            obj.DerivedStacks.(targetStackNameB).writeFrameSet(fovProjection, 1);
        end
        
        function imArrayOut = adjustColorPerChannel(obj, imArrayIn, cropAmount)
                      
            imArrayOut = zeros(size(imArrayIn), 'uint8');
            
            if numel(obj.CurrentChannel) == 1
                imArrayOut = stack.makeuint8(imArrayIn, [], [], cropAmount);      % todo: Generalize this function / add tolerance as input
            else
                imArrayIn = permute(imArrayIn, [1,2,4,3]);
                imArrayOut = permute(imArrayOut, [1,2,4,3]);
                for i = 1:numel(obj.CurrentChannel)
                    imArrayOut(:,:,:,i) = ...
                        stack.makeuint8(imArrayIn(:,:,:,i), [], [], cropAmount);
                end
                imArrayOut = ipermute(imArrayOut, [1,2,4,3]);
            end
        end
        
        function resaveRGBProjectionImages(obj, projectionType)
            % Todo: implement this...

            switch lower( projectionType )
                case 'average'
                    IS = obj.DerivedStacks.AvgFovImage;
                case 'maximum'
                    IS = obj.DerivedStacks.MaxFovImage;
            end
            
            imArray = IS.getFrameSet('all', 'extended');
            filepath = IS.FileName;
            
            % Todo: Need function for makeing RGB out of n-channel stack...
            rgbArray = imArray;
            rgbArray(:, :, 3, :) = 0;
            
            newFilepath = strrep(filepath, '.tif', '_rgb.tif');

            nansen.stack.utility.mat2tiffstack( rgbArray, newFilepath, true ) % true to save as rgb.            
        end
        
        function validateStackSize(~, stackSize)
        %validateStackSize Check if stack has correct size for motion corr    
            
            % todo: channels (and planes)...
            if numel(stackSize) > 3
                %error('Multi channel and/or multiplane stacks are not supported yet')
            elseif numel(stackSize) == 3
                % This is fine:)
            else
                error('Can not motion correct stack with less than 3 dimensions...')
            end
            
        end
        
        function rawStack = openRawTwoPhotonStack(obj)
            
            % Not sure if this will be ever used..
            
            % Get filepath for raw 2p-images
            DATANAME = 'TwoPhotonSeries_Original';
            filePath = obj.SessionObjects.getDataFilePath(DATANAME);
            
            % Initialize file reference for raw 2p-images
            rawStack = nansen.stack.ImageStack(filePath);
            rawStack.enablePreprocessing()
            
        end
        
        function saveAverageProjections(obj)
            
            % Todo:
            % 1: Save fov image per channel and plane
            % 2: 
            
            
            imArray = obj.AvgProjectionStack.getFrameSet(1:obj.NumParts);
            
            imArray = stack.makeuint8(imArray, [], [], crop); % todo: Generalize this function / add tolerance as input
            obj.saveTiffStack('MotionCorrectedAverageProjections8bit', imArray)

            % Save average projection image of full stack
            imArray = obj.AvgProjectionStack.getFrameSet(1:obj.NumParts);
            fovAverageProjection = mean(imArray, 3);
            fovAverageProjection = stack.makeuint8(fovAverageProjection, [], [], crop);
            obj.saveData('FovAverageProjection', fovAverageProjection, ...
                'Subfolder', 'fov_images', 'FileType', 'tif', ...
                'FileAdapter', 'ImageStack' );

        end
        
        % Todo: this should be done using save data method of iomodel
        function saveTiffStack(obj, DATANAME, imageArray)
            
            filePath = obj.getDataFilePath( DATANAME, '-w',...
                'Subfolder', 'motion_corrected', 'FileType', 'tif', ...
                'FileAdapter', 'ImageStack', 'IsInternal', true );
                
            nansen.stack.utility.mat2tiffstack( imageArray, filePath )

        end
        
        
        % Todo: this should be done using load data method of iomodel
        % and an imagestack file adapter.
        function tiffStack = openTiffStack(obj, DATANAME, imageArray, folderName, isInternal)
        %openTiffStack
        
            if nargin < 4; folderName = 'motion_corrected'; end
            if nargin < 5; isInternal = true; end

            filePath = obj.getDataFilePath( DATANAME, '-w',...
                'Subfolder', folderName, 'FileType', 'tif', ...
                'FileAdapter', 'ImageStack', 'IsInternal', isInternal);
            
            props = {'DataDimensionArrangement', ...
                obj.SourceStack.Data.StackDimensionArrangement, ...
                'DataSize', size(imageArray), ...
                'SaveMetadata', true};
            
            if ~isfile(filePath)
                imageData = nansen.stack.open(filePath, imageArray, props{:});
            else
                imageData = nansen.stack.open(filePath, props{:});
            end
            
            if nargout
                tiffStack = nansen.stack.ImageStack(imageData);
            end
        end

        function initializeCorrectionStats(obj, numFrames)
        %initializeCorrectionStats Initialize struct to store stats
        
        %   Save rigid shifts (x and y)
        %   Save rms movement of frames    

            % Check if imreg stats already exist for this session
            filePath = obj.getDataFilePath('MotionCorrectionStats', '-w',...
                'Subfolder', 'motion_corrected', 'IsInternal', true);
            
            % Load or initialize
            if isfile(filePath)
                S = obj.loadData('MotionCorrectionStats');
            else
                nanArray = nan(numFrames, 1);
                
                S.offsetX = nanArray;
                S.offsetY = nanArray;
                S.rmsMovement = nanArray;
                
                % Expand for each channel and/or plane
                S = obj.repeatStructPerDimension(S);
                
                obj.saveData('MotionCorrectionStats', S, ...
                    'Subfolder', 'motion_corrected');
            end
            
            obj.CorrectionStats = S;
            
        end

        % Todo: This should be an external function!
        function S = getImageStats(obj, ~)
            
            % Check if image stats already exist for this session
            filePath = obj.getDataFilePath('ImageStats', '-w', ...
                'Subfolder', 'raw_image_info', 'IsInternal', true);
            
            if isfile(filePath)
                S = obj.loadData('ImageStats');
            else
                error('Image stats was not found')
            end

        end

        function [M, shifts] = correctDrift(obj, M)
            
            % Todo: improve function....
            % Todo: shiftStackSubRes is not part of pipeline.....
            
            % Only need to do this first time...
            sessionRef = obj.ReferenceStack.getFrameSet(1);

            options_rigid = NoRMCorreSetParms('d1', size(M,1), 'd2', size(M,2), ...
                'bin_width', 50, 'max_shift', 20, 'us_fac', 50, ...
                'correct_bidir', false, 'print_msg', 0);
            
            [~, nc_shifts, ~,~] = normcorre(mean(M, 3), options_rigid, sessionRef);
            dx = arrayfun(@(row) row.shifts(2), nc_shifts);
            dy = arrayfun(@(row) row.shifts(1), nc_shifts);

            M = imtranslate(M, [dx,dy] );
            shifts = [dx, dy];
        end
        
    end
    
    methods (Static) % Method in external file (Get default options)
        
        S = getDefaultOptions()

    end

end