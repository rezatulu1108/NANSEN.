classdef SessionData < dynamicprops & matlab.mixin.CustomDisplay & applify.mixin.UserSettings
%SessionData Class that provides access to File Variables in DataLocations 
% 
%
%

% NOTE: This class overrides the subsref method and although private
% properties and methods are accounted for, there could be issues if
% subclassing this class and implementing protected properties. Long story
% short, protected properties would not be protected in this case.
% Another issue if trying something like {sessionData.RoiArray.area}, wont
% work, so assign roiArray to another variable first

% Note: This class is not yet well adapted non-scalar objects!


% Todo: 
%   [v] Should hold the session object and call methods from the session
%       object, instead of running a copy of those methods....
%   [ ] Remove all methods that are duplicates from the session class.

    properties (Constant, Hidden)
        USE_DEFAULT_SETTINGS = false;
        DEFAULT_SETTINGS = nansen.session.SessionData.getDefaultSettings()
    end

    properties
        sessionID
    end
    
    properties (Dependent, Hidden)
        IsInitialized;
    end

    properties (Access = private)
        DataLocation
        subjectID 
        Date 
        Time
    end
    
    properties (Access = private)
        SessionObject
        DataLocationModel
        DataFilePathModel
    end
    
    properties (Access = private)
        State = 'uninitialized';
        VariableList struct
        FileList containers.Map
    end
    
    properties (Access = private, Dependent)
        VariableNames
    end
    
    
    methods (Hidden) % Constructor
        
        function obj = SessionData(sessionObj)
            
            obj.SessionObject = sessionObj;
                        
            % Inherit properties for sessionObj. Todo: Avoid duplication...       
            obj.sessionID = sessionObj.sessionID;
% %             obj.subjectID = sessionObj.subjectID;
% %             obj.Date = sessionObj.Date;
% %             obj.Time = sessionObj.Time;
% %             obj.DataLocation = sessionObj.DataLocation;

            
            % Initialize the property value here (because Map is handle)
            obj.FileList = containers.Map; % Todo: Use java.HashTable or similar instead?
            
        end
        
    end
    
    methods
        
        function obj = initialize(obj)
        %initialize Initialize the variables of session
            fprintf('Initializing session data variables...\n')
            obj.updateDataVariables();
        end
        
        function obj = update(obj)
            fprintf('Updating session data variables...\n')
            obj.updateDataVariables();
        end
        
    end
    
    methods 
        function dlModel = get.DataLocationModel(obj)
            dlModel = obj.SessionObject.DataLocationModel;
        end
        
        function varNames = get.VariableNames(obj)
            if isempty(obj.VariableList)
                varNames = {};
            else
                varNames = {obj.VariableList.VariableName};
            end
        end
        
        function tf = get.IsInitialized(obj)
            if strcmp(obj.State, 'uninitialized')
                tf = false;
            elseif strcmp(obj.State, 'initialized')
                tf = true;
            end
        end
        
    end
    
    methods (Hidden)
        
        function obj = showInternalVariables(obj)
            obj.settings.ShowInternalVariables = true;
        end
        
        function obj = hideInternalVariables(obj)
            obj.settings.ShowInternalVariables = false;
        end
        
        function obj = showFavouriteVariables(obj)
            obj.settings.ShowFavouriteVariables = true;
        end
        
        function obj = hideFavouriteVariables(obj)
            obj.settings.ShowFavouriteVariables = false;
        end
                
        function obj = showDefaultVariables(obj)
            obj.settings.ShowDefaultVariables = true;
        end
        
        function obj = hideDefaultVariables(obj)
            obj.settings.ShowDefaultVariables = false;
        end
        
        function obj = showUserVariables(obj)
            obj.settings.ShowUserVariables = true;
        end
        
        function obj = hideUserVariables(obj)
            obj.settings.ShowUserVariables = false;
        end
        

        function updateDataVariables(obj)
            
            if isempty(obj.SessionObject.DataLocationModel)
                % Todo: Consider to throw an error.
                fprintf('Aborted, this session does not have a DataLocationModel')
                return
            end
            
            obj.DataFilePathModel = nansen.setup.model.FilePathSettingsEditor();
            varNames = {obj.DataFilePathModel.VariableList.VariableName};
            
            for i = 1:numel(varNames)
                try
                    filePath = obj.SessionObject.getDataFilePath(varNames{i});

                    if isfile(filePath)
                        if ~isprop(obj, varNames{i})
                            obj.addDataProperty(varNames{i})
                            obj.appendToVariableList(obj.DataFilePathModel.VariableList(i))
                        end
                    end
                catch
                    % Todo: Find if session folder is not found, otherwise
                    % need to do something...
                end
            end
            
            obj.State = 'initialized';
            
        end

        function varNames = getDataType(obj, typeName)
            
            % Todo: get from session object.
            dataFilePathModel = nansen.setup.model.FilePathSettingsEditor;
            
            fileAdapters = {dataFilePathModel.VariableList.FileAdapter};
            
            switch typeName
                case {'RoiGroup', 'RoiArray'}
                    varNames = {'roiArrayQuickyAuto', 'roiArrayExtractAuto', 'roiArray'};
                    
                otherwise
                    tf = strcmp(fileAdapters, typeName);
                    varNames = {dataFilePathModel.VariableList(tf).VariableName};
            end
            
            tf = false(1, numel(varNames));
            for i = 1:numel(varNames)
                tf(i) = isprop(obj, varNames{i} );
            end
            
            varNames = varNames(tf);
        end
        
        function varNames = uiSelectVariableName(obj, dataType, selectionMode)
        %uiSelectVariableName Open dialog to select variable from sdata
        %------------------------------------------------------------------
        %
        %   SYNTAX:
        %
        %   varNames = obj.uiSelectVariableName() opens a dialog to select
        %   on or more variables that are available in SessionData object
        %
        %   varNames = obj.uiSelectVariableName(dataType) lets user select
        %   among variables from the specified dataType
        %
        %   varNames = obj.uiSelectVariableName(dataType, selectionMode)
        %   additionally determines the selection mode. selectionMode can
        %   be 'multi' (Default) or 'single'.
        %
        %   OUTPUT:
        %       varNames : cell array of variable name(s)
        
        
            if nargin < 2
                varNames = obj.VariableNames;
            else
                varNames = obj.getDataType(dataType);
            end
            
            if nargin < 3; selectionMode = 'multi'; end
            
            if isempty(varNames)
                if exist('dataType', 'var')
                    error('No variable is available for data type "%s"', dataType)
                else
                    error('No variable is available')
                end
            end
            
            if numel(varNames) == 1
                return
            end
            
            
            msg = 'Select a data variable:';
            [indx, tf] = listdlg('ListString', varNames, ...
                'PromptString', msg, 'SelectionMode', selectionMode);
            
            if tf
                varNames = varNames(indx);
            else
                varNames = {};
            end
            
        end
        
    end
    
    methods (Access = protected)
        
        function addDataProperty(obj, variableName)
            pPuplic = obj.addprop(variableName);
            
            % Add a private property that will hold the actual data.
            privateVariableName = strcat(variableName, '_');
            pPrivate = obj.addprop(privateVariableName);
            pPrivate.SetAccess = 'private';
            pPrivate.GetAccess = 'private';
            
            %obj.(privateVariableName) = [];
            
            pPuplic.GetMethod = @(h, varName) obj.getDataVariable(variableName);
            
            %pPuplic.SetMethod = @obj.setDataVariable;
            pPuplic.SetAccess = 'private'; %todo: Add set functionality

        end
        
        function appendToVariableList(obj, variableItem)
            if isempty(obj.VariableList)
                obj.VariableList = variableItem;
            else
                obj.VariableList(end+1) = variableItem;
            end
        end
        
        function value = getDataVariable(obj, varName)
            privateVarName = strcat(varName, '_');
            
            if isempty(obj.(privateVarName))
                value = 'Unassigned';
            else
                value = obj.(privateVarName);
            end

        end
        
        function assignDataToPrivateVar(obj, varName)
            privateVarName = strcat(varName, '_');
            
            if isempty(obj.(privateVarName))
                obj.(privateVarName) = obj.loadData(varName); 
            end
            
        end
        
        function setDataVariable(obj, varargin)
            disp('variables can only be read for now')
        end
        
        function str = getHeader(obj)
            str = getHeader@matlab.mixin.CustomDisplay(obj);
            
            className = strrep(class(obj), 'nansen.session.', '');
            
            if numel(obj) == 1
                if strcmp(obj.State, 'uninitialized')
                    className = sprintf('%s (%s)', className, obj.State);
                end
            end
            
            str = strrep(str, '>SessionData<', sprintf('>%s<', className));
            
            if numel(obj) == 1
                str = strrep(str, 'properties', 'data variables');
            else
                str = strrep(str, 'with properties:', '(variables not displayable for non-scalar SessionData)');
            end
            
            % Todo: Improve header for arrays
        end
        
        function propGroup = getPropertyGroups(obj)
            
            % Initialize output variable as empty
            propGroup = matlab.mixin.util.PropertyGroup.empty;

            if numel(obj) > 1
                return
                % Todo: Improve property groups for arrays!
            end
            
            if strcmp(obj(1).State, 'uninitialized') ...
                    || isempty(obj(1).VariableList)
                return;
            end
            
            isDefault = [obj(1).VariableList.IsDefaultVariable];
            
            internal = []; %Todo
            isDefault(internal) = false;
            
            propGroup = matlab.mixin.util.PropertyGroup.empty;
            
            favIdx = []; %Todo
            internal = ~isDefault;
            isUser = [];

            
            if obj.settings.ShowFavouriteVariables && any(favIdx)
                propNames = sort( {obj.VariableList(favIdx).VariableName} ); 
                propGroup = [propGroup, matlab.mixin.util.PropertyGroup(propNames, 'Favourite Variables:')];
            end
            
            if obj.settings.ShowDefaultVariables && any(isDefault)
                propNames = sort( {obj.VariableList(isDefault).VariableName} ); 
                propGroup = [propGroup, matlab.mixin.util.PropertyGroup(propNames, 'Default Variables:')];
            end
            
            if obj.settings.ShowUserVariables && any(isUser)
                propNames = sort( {obj.VariableList([]).VariableName} ); 
                propGroup = [propGroup, matlab.mixin.util.PropertyGroup(propNames, 'User Variables:')];
            end
            
            if obj.settings.ShowInternalVariables && any(internal)
                propNames = sort( {obj.VariableList(internal).VariableName} ); 
                propGroup = [propGroup, matlab.mixin.util.PropertyGroup(propNames, 'Internal Variables:')];
            end
            
        end
        
        function onSettingsChanged(obj, name, value)
            % Pass
        end
    end
    
    methods (Sealed, Hidden)
        
        function T = addprop(obj, varargin)
            T = addprop@dynamicprops(obj, varargin{:});
            if ~nargout; clear T; end
        end
        
        function varargout = subsref(obj, s)
            
            % Preallocate cell array of output.
            varargout = cell(1, nargout);

            switch s(1).type

                % I only want to override the variable names that are added
                % as dynamic properties. If the user request this property,
                % we should load the data from file
                
                case '.'
                    if any(strcmp(obj.VariableNames, s(1).subs))
                        obj.assignDataToPrivateVar(s(1).subs)
                        
                    else % Take appropriate action if a property or method is requested.
                    
                        mc = metaclass(obj);
                        throwError = false;

                        % Test if a public property or method was invoked
                        if isprop(obj, s(1).subs)
                            isMatch = strcmp({mc.PropertyList.Name}, s(1).subs);

                            if any(isMatch)
                                getAccessStr = mc.PropertyList(isMatch).GetAccess;
                                if ~strcmpi(getAccessStr, 'public')
                                    throwError = true;
                                end
                            else
                                throwError = true;
                            end

                        elseif ismethod(obj, s(1).subs)
                            % Public method
                        else
                            isMatch = strcmp({mc.MethodList.Name}, s(1).subs);

                            if any(isMatch)
                                accessStr = mc.MethodList(isMatch).Access;

                                if ~strcmpi(accessStr, 'public')
                                    throwError = true;
                                end
                            else
                                throwError = true;
                            end
                        end

                        if throwError
                            errorID = 'MATLAB:noSuchMethodOrField';
                            errorMsg = sprintf('Unrecognized method, property, or field ''%s'' for class ''%s''.', s(1).subs, class(obj));
                            throwAsCaller(MException(errorID, errorMsg))
                        end
                        
                    end

            end
              
            % If we got this far, use the builtin subsref
            if nargout > 0
                [varargout{:}] = builtin('subsref', obj, s);
            else
                try
                    varargout{1} = builtin('subsref', obj, s);
                catch ME
                    switch ME.identifier
                        case {'MATLAB:TooManyOutputs', 'MATLAB:maxlhs'}
                            try
                                builtin('subsref', obj, s)
                            catch ME
                                rethrow(ME)
                            end
                        otherwise
                            rethrow(ME)
                    end
                end
            end
                    
        end

    end
            
    methods (Access = protected) % Load data variables
        
        function data = loadData(obj, varName, varargin)
            
            % TODO:
            %   [ ] Implement file adapters.
            
            filePath = obj.getDataFilePath(varName, '-r', varargin{:});

            if isfile(filePath)
                
                [~, ~, ext] = fileparts(filePath);
                
                switch ext
                    case '.mat'
                        S = load(filePath, varName);
                        if isfield(S, varName)
                            data = S.(varName);
                        else
                            S = load(filePath);
                            data = S;
        %                 else
        %                     error('File does not hold specified variable')
                        end
                        
                    case {'.raw', '.tif'}
                        data = nansen.stack.ImageStack(filePath);
                        
                    otherwise
                        error('Nansen:Session:LoadData', 'Files of type ''%s'' is not supported for loading', ext)
 
                end
                

            else
                error('File not found')
            end
            
        end
        
        function saveData(obj, varName, data, varargin)
            
            % TODO:
            %   [ ] Implement file adapters.
            
            filePath = obj.getDataFilePath(varName, '-w', varargin{:});
            
            S.(varName) = data;
            save(filePath, '-struct', 'S')
            
        end
        
        function pathStr = getDataFilePath(obj, varName, varargin)
        %getDataFilePath Get filepath to data within a session folder
        %
        %   pathStr = sessionObj.getDataFilePath(varName) returns a
        %   filepath (pathStr) for data with the given variable name 
        %   (varName).
        %
        %   pathStr = sessionObj.getDataFilePath(varName, mode) returns the
        %   filepath subject to the specified MODE:
        %       '-r'    : Get filepath of existing file (Default)
        %       '-w'    : Get filepath of existing file or create filepath
        %
        %   pathStr = sessionObj.getDataFilePath(__, Name, Value) uses 
        %   name-value pair arguments to control aspects of the filename.
        %
        %   PARAMETERS:
        %
        %       Subfolder : If file is in a subfolder of sessionfolder.
        %
        %
        %   EXAMPLES:
        %
        %       pathStr = sObj.getFilePath('dff', '-w', 'Subfolder', 'roisignals')
        
            
            % Todo: 
            %   [ ] (Why) do I need mode here?
            %   [ ] Implement load/save differences, and default datapath
            %       for variable names that are not defined.
            %   [ ] Implement ways to grab data spread over multiple files, i.e
            %       if files are separate by imaging channel, imaging plane,
            %       trials or are just split into multiple parts...
            
            
            pathStr = obj.SessionObject.getDataFilePath(varName, varargin{:});
            return
            
            % Get the model for data file paths.
            global dataFilePathModel
            if isempty(dataFilePathModel)
                dataFilePathModel = nansen.setup.model.FilePathSettingsEditor;
            end

            % Check if mode is given as input:
            [mode, varargin] = obj.checkDataFilePathMode(varargin{:});
            parameters = struct(varargin{:});
            
            % Get the entry for given variable name from model
            [S, isExistingEntry] = dataFilePathModel.getEntry(varName);
        
            if ~isExistingEntry
                S = utility.parsenvpairs(S, [], parameters);
            end
            
            % Get path to session folder
            sessionFolder = obj.getSessionFolder(S.DataLocation);
            
            % Check if file should be located within a subfolder.
            if ~isempty(S.Subfolder)
                dataFolder = fullfile(sessionFolder, S.Subfolder);
                
                if ~isfolder(dataFolder) && strcmp(mode, 'write')
                    mkdir(dataFolder)
                end
            else
                dataFolder = sessionFolder;
            end
            
            
            if isempty(S.FileNameExpression)
                fileName = obj.createFileName(varName, S);
            else
                fileName = obj.lookForFile(dataFolder, S);
                if isempty(fileName)
                    fileName = obj.getFileName(S);
                end
            end
            
            pathStr = fullfile(dataFolder, fileName);
            
            % Save filepath entry to filepath settings if it did
            % not exist from before...
            if ~isExistingEntry && strcmp(mode, 'write')
                dataFilePathModel.addEntry(S)
            end
            
        end
        
        function [mode, varargin] = checkDataFilePathMode(~, varargin)
            
            % Default mode is read:
            mode = 'read';
            
            if ~isempty(varargin) && ischar(varargin{1})
                switch varargin{1}
                    case '-r'
                        mode = 'read';
                        varargin = varargin(2:end);
                    case '-w'
                        mode = 'write';
                        varargin = varargin(2:end);
                end
            end
            
        end
        
        function fileName = lookForFile(obj, sessionFolder, S)

            % Todo: Move this method to filepath settings editor.
            
            expression = S.FileNameExpression;
            fileType = S.FileType;
            
            if contains(expression, fileType)
                expression = ['*', expression];
            else
                expression = ['*', expression, fileType]; % Todo: ['*', expression, '*', fileType] <- Is this necessary???
            end
            
            
            % Is this faster if there are many files?
% % %             if isKey(obj.FileList, sessionFolder)
% % %                 fileList = obj.FileList(sessionFolder);
% % %             else
% % %                 L = dir(sessionFolder);
% % %                 L = L(~strncmp({L.name}, '.', 1));
% % %                 fileList = {L.name};
% % %                 obj.FileList(sessionFolder) = fileList;
% % %             end
% % % 
% % %             expression = strrep(expression, '*', '')
% % %             isMatch = contains(fileList, expression);
% % %             if any(isMatch) && sum(isMatch)==1
% % %                 fileName = fileList{isMatch};
% % %             elseif any(isMatch) && sum(isMatch) < 1
% % %                 error('Multiple files were found')
% % %             else
% % %                 fileName = '';
% % %             end
            
            L = dir(fullfile(sessionFolder, expression));
            L = L(~strncmp({L.name}, '.', 1));
            
            if ~isempty(L) && numel(L)==1
                fileName = L.name;
            elseif ~isempty(L) && numel(L)>1
                error('Multiple files were found')
            else
                fileName = '';
            end
            
        end
        
        function fileName = createFileName(obj, varName, parameters)
            
            sid = obj.sessionID;
            
            capLetterStrInd = regexp(varName, '[A-Z, 1-9]');

            for i = fliplr(capLetterStrInd)
                if i ~= 1
                    varName = insertBefore(varName, i , '_');
                end
            end
            
            varName = lower(varName);
            
            fileName = sprintf('%s_%s', sid, varName);
            
            if isfield(parameters, 'FileType')
                fileExtension = parameters.FileType;
                if ~strncmp(fileExtension, '.', 1)
                    fileExtension = strcat('.', fileExtension);
                end
            else
                fileExtension = '.mat';
            end
            
            fileName = strcat(fileName, fileExtension);

        end
        
        function fileName = getFileName(obj, S)
            
            sid = obj.sessionID;

            fileName = sprintf('%s_%s', sid, S.FileNameExpression);
            
            fileType = S.FileType;
            
            if ~strncmp(fileType, '.', 1)
                fileType = strcat('.', fileType);
            end
            
            fileName = strcat(fileName, fileType);
            
        end

        function folderPath = getSessionFolder(obj, dataLocationName)
        % Get session folder for session given a dataLocationType
        
            % Todo: implement secondary roots (ie cloud directories)
            
            folderPath = obj.SessionObject.getSessionFolder(dataLocationName);
           
        end

    end
   
    methods (Static)
        function S = getDefaultSettings()
            
            S = struct;
            S.ShowDefaultVariables = true;
            S.ShowUserVariables = true;
            S.ShowInternalVariables = true;
            S.ShowFavouriteVariables = true;
            
        end
    end
end