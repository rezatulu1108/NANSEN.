classdef ScanImageTiff < nansen.stack.data.VirtualArray
%ScanImageTiff Virtual data adapter for a scanimage tiff file

% Note: Multi plane stacks are not supported.

properties (Constant, Hidden)
    FILE_PERMISSION = 'read'
end

properties (Access = private, Hidden)
    hTiffStack  % TIFFStack object
    tiffInfo    % TIFF object
end

properties (Access = private, Hidden) % File Info
    UseTiffStack = false % Flag whether to use DylanMuirs TIFFStack class

    NumChannels_
    NumPlanes_
    NumTimepoints_
    
    FrameIndexMap   % Holds frame indices for interleaved dimensions (numC x numZ x numT)
    % Todo: Replace with deinterleaver..
end

methods % Structors
    
    function obj = ScanImageTiff(filePath, varargin)
        
        % Todo: document and make sure it always works to receive a tiff
        % object instead of a filepath as input
        
        obj@nansen.stack.data.VirtualArray(filePath, varargin{:})
        
    end
    
    function delete(obj)
        
        if ~isempty(obj.hTiffStack)
            delete(obj.hTiffStack)
        end
        
        if ~isempty(obj.tiffInfo)
            close(obj.tiffInfo)
        end

    end
    
end


methods (Access = protected) % Implementation of abstract methods
        
    function assignFilePath(obj, filePath, ~)
        
        if isa(filePath, 'cell')
            if ischar( filePath{1} )
                obj.FilePath = filePath{1};
            elseif isa(filePath{1}, 'Tiff')
            	obj.tiffInfo = filePath{1};
                obj.FilePath = obj.tiffInfo.FileName;
            end
            
        elseif isa(filePath, 'char') || isa(filePath, 'string')
            obj.FilePath = char(filePath);
            
        elseif isa(filePath, 'Tiff') 
            obj.tiffInfo = filePath;
            obj.FilePath = obj.tiffInfo.Filename;
        end
        
        % Determine whether TIFFStack is on path and should be used.
        if exist('TIFFStack', 'file') == 2
            obj.UseTiffStack = false;
        end
        
    end
    
    function getFileInfo(obj)
        
        if isempty( obj.tiffInfo )
            obj.tiffInfo = Tiff(obj.FilePath);
        end
        
        obj.assignDataSize()
        
        obj.assignDataType()

    end
    
    function createMemoryMap(obj)
        
        % This should already have happened in assignDataSize
        if ~isempty(obj.hTiffStack)
           return 
        end
        
        if obj.UseTiffStack % Use Dylan Muirs TIFFStack class.
            numDirs = obj.NumChannels_ * obj.NumTimepoints_;
        
            warning('off', 'TIFFStack:SlowAccess')
            warning('off', 'TIFFStack:LongStack')

            obj.hTiffStack = TIFFStack(obj.FilePath, [], ...
                obj.NumChannels_, false, numDirs);
            warning('on', 'TIFFStack:SlowAccess')
            warning('on', 'TIFFStack:LongStack')
            
        else
            
            numFrames = obj.NumChannels_ * obj.NumPlanes_ * obj.NumTimepoints_;
            frIndMap = 1:numFrames;
            
            frIndMap = reshape(frIndMap, obj.NumChannels_, obj.NumPlanes_, obj.NumTimepoints_);
            obj.FrameIndexMap = squeeze(frIndMap);
        
        end

    end
    
    function assignDataSize(obj)
        
        % Todo: Verify that data is saved in order y,x,c,z,t
        
        % Get scan image tiff header
        evalc(obj.tiffInfo.getTag('ImageDescription'));
        evalc(obj.tiffInfo.getTag('Software'));
        
        obj.DataSize(1) = obj.tiffInfo.getTag('ImageLength');
        obj.DataSize(2) = obj.tiffInfo.getTag('ImageWidth');
        %obj.ImageSize(1) = SI.hRoiManager.linesPerFrame;
        %obj.ImageSize(2) = SI.hRoiManager.pixelsPerLine;
        
        % Specify data dimension sizes
        obj.MetaData.SizeX = obj.DataSize(2);
        obj.MetaData.SizeY = obj.DataSize(1);
        obj.DataDimensionArrangement = 'YX';

        % Specify physical sizes
        obj.MetaData.TimeIncrement = SI.hRoiManager.scanFramePeriod;
        
        % Todo: Is there a better way to get the physical image size?
        obj.MetaData.ImageSize = abs( sum(SI.hRoiManager.imagingFovUm(1,:) ));
        %obj.MetaData.PhysicalSizeY = nan;
        %obj.MetaData.PhysicalSizeX = nan;
        obj.MetaData.PhysicalSizeYUnit = 'micrometer'; % Todo: Will this always be um?
        obj.MetaData.PhysicalSizeXUnit = 'micrometer'; % Todo: Will this always be um?
        obj.MetaData.SampleRate = SI.hRoiManager.scanVolumeRate;
        
        obj.NumTimepoints_ = SI.hStackManager.framesPerSlice;

        % Determine dimensions C, Z, T:
        obj.NumChannels_ = numel( SI.hChannels.channelSave );
        obj.NumPlanes_ = SI.hStackManager.numSlices;
        obj.countNumFrames();

        % Add length of channels if there is more than one channel
        if obj.NumChannels_ > 1
            obj.DataSize = [obj.DataSize, obj.NumChannels_];
            obj.DataDimensionArrangement(end+1) = 'C';
        end
        
        % Add length of planes if there is more than one plane
        if obj.NumPlanes_ > 1
            obj.DataSize = [obj.DataSize, obj.NumPlanes_];
            obj.DataDimensionArrangement(end+1) = 'Z';
        end
        
        % Add length of sampling dimension.
        if obj.NumTimepoints_ > 1
            obj.DataSize = [obj.DataSize, obj.NumTimepoints_];
            obj.DataDimensionArrangement(end+1) = 'T';
        end
    end
    
    function assignDataType(obj)
        
        % Todo: Should be part of a tiff superclass
        sampleFormat = obj.tiffInfo.getTag('SampleFormat');
        bitsPerSample = obj.tiffInfo.getTag('BitsPerSample');
        
        switch sampleFormat
            case 1
                obj.DataType = sprintf('uint%d', bitsPerSample);
            case 2
                obj.DataType = sprintf('int%d', bitsPerSample);
            case 3
                
            otherwise
                error('Tiff file is not supported')
        end
    end
    
end

methods % Implementation of VirtualArray abstract methods
    
    function data = readData(obj, subs)
    %readData Reads data from tiff file
    %
    %   See also nansen.stack.data.VirtualArray/readData
    
        if ~isempty(obj.hTiffStack)
            data = obj.hTiffStack(subs{:});
        else
            data = obj.readDataTiff(subs);
        end
    end
    
    function data = readFrames(obj, frameIndex)
        
        subs = cell(1, ndims(obj));
        subs(1:2) = {':'};
        
        if isa(frameIndex, 'cell')
            nCells = numel(frameIndex);
            subs(end-nCells+1:end) = frameIndex;
        elseif isnumeric(frameIndex)
            subs(end) = {frameIndex};
        end
        
        data = obj.readData(subs);
        
    end
    
    function data = readDataTiff(obj, subs)
        
        % Determine size of requested data
        dataSize = obj.getOutSize(subs);
        
        % Preallocate data
        data = zeros(dataSize, obj.DataType);
        insertSub = arrayfun(@(n) 1:n, dataSize, 'uni', 0);
        
        global waitbar
        useWaitbar = false;
        if ~isempty(waitbar); useWaitbar = true; end
        
        if useWaitbar
            waitbar(0, 'Loading image frames')
            updateRate = round(dataSize(end)/50);
        end
        
        frameInd = obj.FrameIndexMap(subs{3:end});

        [m, n, p] = size(frameInd);
        numFramesToLoad = m*n*p;

        count = 1;
        
        % Loop through frames and load into data.
        for k = 1:p
            for j = 1:n
                for i = 1:m
                    frameNum = frameInd(count);
                    insertSub(3:5) = {i, j, k};
                    
                    obj.tiffInfo.setDirectory(frameNum);
                    data(insertSub{:}) = obj.tiffInfo.read();

                    count = count + 1;
            
                    if useWaitbar
                        if mod(count, updateRate) == 0
                            waitbar(count/numFramesToLoad, 'Loading image frames')
                        end
                    end
                end
            end
        end
        
        data = obj.cropData(data, subs);
    end
    
    function writeFrames(obj, frameIndex, data)
        error('Not implemented yet')
    end
    
end


methods (Access = private)
    
    function dataSize = getOutSize(obj, subs)
    %getOutSize Get size of data requested by subs...
    %
    %   INPUT
    %       subs : subscripts with indices for each dimension of data
    %   OUTPUT
    %       dataSize : size of data to read

        dataSize = zeros(1, numel(subs));

        for i = 1:numel(subs)
            if ischar(subs{i}) && isequal(subs{i}, ':')
                dataSize(i) = obj.DataSize(i);
            else
                thisDim = obj.DataDimensionArrangement(i);
                if any( strcmp({'X', 'Y'}, thisDim) )
                    dataSize(i) = obj.DataSize(i);
                else
                    dataSize(i) = numel(subs{i});
                end
            end
        end
    end
    
    function countNumFrames(obj)
    %countNumFrames 
            
        import nansen.stack.utility.findNumTiffDirectories

        % USING TIFF:
        n = findNumTiffDirectories(obj.tiffInfo, 1, 10000);
        obj.NumTimepoints_ = n ./ obj.NumChannels_ ./ obj.NumPlanes_;
        return
    
        % Need to create the memorymap in order to correct the framecount.
        obj.createMemoryMap()
        
        % Use the TIFFStack object and trial/error to get the correct
        % framecount. 
        frame_low = 1;
        frame_high = obj.NumTimepoints_;
        frame_current = frame_high;
        
        while frame_high - frame_low > 1
            try
                im = obj.hTiffStack(:,:, obj.NumChannels_, frame_current);
                frame_low = frame_current;
            catch e
                frame_high = frame_current;
            end
            
            frame_current = frame_low + floor((frame_high - frame_low)/2);
        end
        
        obj.NumTimepoints_ = frame_current;
    end
    
end


methods (Static)
    
    function createFile(filePath, arraySize, arrayClass)
        error('Creation of ScanImage Tiffs are not supported.')
    end

    function isValid = fileCheck(pathStr)
    %fileCheck Check if filepath points to a scanimage file
        
        isValid = false;

        if isa(pathStr, 'cell')
            pathStr = pathStr{1};
        end

        [~, ~, fileExtension] = fileparts(pathStr);

        switch lower(fileExtension)
            
            case {'.tif', '.tiff'}
                
                if isfile(pathStr)
                    % Get tiff info, but supress a common warning
                    warning('off', 'imageio:tiffmexutils:libtiffWarning')
                    imInfo = Tiff(pathStr);
                    warning('on', 'imageio:tiffmexutils:libtiffWarning')

                    % Check if the tiff 'Software' tag contains SI
                    try 
                        softwareName = imInfo.getTag('Software');
                        if strcmp(softwareName(1:2), 'SI')
                            isValid = true;
                        end
                    catch
                        % Not valid
                    end

                else
                    % Not valid
                end
            
            otherwise 
                % Not valid (not aware of any other file formats)
        end
    end

end

end