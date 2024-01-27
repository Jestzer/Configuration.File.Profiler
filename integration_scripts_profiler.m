function integration_scripts_profiler

% Get the release number.
versionOutput = version;
pattern = '\((.*?)\)';
tokens = regexp(versionOutput, pattern, 'tokens');

% Check if any parentheses were found for "version".
if ~isempty(tokens)
    versionNumber = tokens{1}{1}; % tokens is a cell array of cell arrays. Neat!
    versionNumber = versionNumber(2:end); % Remove the R since it's often already included.
    environmentVariableToSet = 'MATLAB_VERSION_STRING';
    setenv(environmentVariableToSet, versionNumber)
else
    error('MATLAB release number could not be parsed. Exiting.');
end

% Get the full path to the currently running function and any .conf files in it.
functionFullPath = mfilename('fullpath');
functionDir = fileparts(functionFullPath);
confSearchPath = fullfile(functionDir, '*.conf');
confFiles = dir(confSearchPath);

if ~isempty(confFiles)

    % Find all .conf files and assign a number to each found.    
    for i = 1:length(confFiles)
    end

    if i == 1
        selectedIndex = 1;
    else % Select a .conf file if you have multiple.
        fprintf('Multiple .conf files found:\n');
        for i = 1:length(confFiles)
            fprintf('%d: %s\n', i, confFiles(i).name);
        end
        selectedIndex = input('Select a .conf file by number: ');
    
        % Validate user input.
        if selectedIndex < 1 || selectedIndex > length(confFiles) || ~isnumeric(selectedIndex) || ~mod(selectedIndex, 1) == 0
            error('Invalid selection. Exiting.');
        end
    end

    
    % Get the selected .conf file name.
    confFileName = confFiles(selectedIndex).name;
    fprintf('Configuration file selected: %s\n', confFileName);
else
    error('No .conf file found in the same directory as this function. Exiting.');
end

% Determine the operating system.
isWindows = ispc;
isUnix = isunix || ismac;

% Open the .conf file for reading
fileID = fopen(confFileName, 'r');
if fileID == -1
    error('Failed to open .conf file: %s\n', confFileName);
end

% Create the profile
clusterName = '';
c = parallel.cluster.Generic;

% Set all general cluster profile properties by reading line by line BEFORE [AdditionalProperties] is found.
while ~feof(fileID)
    line = fgetl(fileID);
    line = strtrim(line); % Trim whitespace from both ends of the line

    if strcmp(line, '[AdditionalProperties]')
        break; % End general property processing and move onto AdditionalProperties.
    end

    % Ignore commented or blank lines.
    if ~startsWith(line, '#') && ~isempty(line)
        parts = strsplit(line, '=');
        if numel(parts) == 2
            propertyName = strtrim(parts{1});
            propertyValue = strtrim(parts{2});

            % Remove any double quotation marks from propertyValue.
            propertyValue = strrep(propertyValue, '"', '');

            % Get environment variables when used.
            if contains(propertyValue, '$')
                pattern = '\$(\w+)';
                tokens = regexp(propertyValue, pattern, 'tokens');

                if ~isempty(tokens)
                    % Extract the first token which should be the environment variable name
                    envVarName = tokens{1}{1};
                    envVarValue = getenv(envVarName);

                    % Replace the occurrence of the environment variable in the original string
                    propertyValue = strrep(propertyValue, ['$' envVarName], envVarValue);
                end
            end

            % Check for OS-specific properties.
            if contains(propertyName, '(Windows)') && isWindows
                propertyName = strrep(propertyName, '(Windows)', '');
                propertyName = strtrim(propertyName);
            elseif contains(propertyName, '(Unix)') && isUnix
                propertyName = strrep(propertyName, '(Unix)', '');
                propertyName = strtrim(propertyName);
            elseif contains(propertyName, '(Windows)') || contains(propertyName, '(Unix)')                
                continue; % OS does not match, skip this property.
            end

            if strcmp(propertyName, 'Name')
                clusterName = propertyValue;
                c.saveAsProfile(clusterName);
            elseif contains(propertyName, 'PluginScriptsLocation')

                if contains(versionNumber, '2017') || contains(versionNumber, '2018') % Change the name in older releases.
                    propertyName = strrep(propertyName, 'PluginScriptsLocation', 'IntegrationScriptsLocation');
                end
            elseif strcmp(propertyName, 'JobStorageLocation')

                % Check if the job storage location exists.
                if ~exist(propertyValue, 'dir')
                    [success, message, ~] = mkdir(propertyValue); % The directory does not exist, attempt to create it.

                    % Check if the directory was successfully created.
                    if success
                        disp(['Job storage location created: ', propertyValue]);
                    else
                        error(['Failed to create job storage location specified: ', message]);
                    end
                else
                    % The directory already exists.
                end
            % Set booleans and doubles correctly.
            elseif isempty(propertyValue)
                % Do nothing.
            elseif strcmpi(propertyValue, 'true')
                propertyValue = true;
            elseif strcmpi(propertyValue, 'false')
                propertyValue = false;
            elseif all(isstrprop(propertyValue, 'digit'))
                propertyValue = str2double(propertyValue);
            end

            % You can't actually edit a profile name from the command line. It must be saved as a new profile (which is done at the end.)
            if ~strcmp(propertyName, 'Name')
                % Set the retrieved property name and value on the cluster profile temporarily.
                c.(propertyName) = propertyValue;
            end
            
        end
    end
end

frewind(fileID); % Reset the file pointer to the beginning of the file before the second while loop. Otherwise, this whole section is ignored.

inAdditionalPropertiesSection = false;

% Set all AdditionalProperties by reading line by line after [AdditionalProperties] is found.
while ~feof(fileID)
    line = fgetl(fileID);
    line = strtrim(line); % Trim whitespace from both ends of the line

    if strcmp(line, '[AdditionalProperties]')
        inAdditionalPropertiesSection = true;
        continue; % Skip processing this line and move to the next one
    end

    % Ignore commented or blank lines.
    if inAdditionalPropertiesSection && ~startsWith(line, '#') && ~isempty(line)
        parts = strsplit(line, '=');
        if numel(parts) == 2
            propertyName = strtrim(parts{1});
            propertyValue = strtrim(parts{2});

            % Remove any double quotation marks from propertyValue.
            propertyValue = strrep(propertyValue, '"', '');

            % Get environment variables when used.
            if contains(propertyValue, '$')
                pattern = '\$(\w+)';
                tokens = regexp(propertyValue, pattern, 'tokens');

                if ~isempty(tokens)
                    % Extract the first token which should be the environment variable name
                    envVarName = tokens{1}{1};
                    envVarValue = getenv(envVarName);

                    % Replace the occurrence of the environment variable in the original string
                    propertyValue = strrep(propertyValue, ['$' envVarName], envVarValue);
                end
            end

            % Check for OS-specific properties.
            if contains(propertyName, '(Windows)') && isWindows
                propertyName = strrep(propertyName, '(Windows)', '');
                propertyName = strtrim(propertyName);
            elseif contains(propertyName, '(Unix)') && isUnix
                propertyName = strrep(propertyName, '(Unix)', '');
                propertyName = strtrim(propertyName);
            elseif contains(propertyName, '(Windows)') || contains(propertyName, '(Unix)')                
                continue; % OS does not match, skip this property.
            end

            % Set booleans and doubles correctly.
            if isempty(propertyValue)
                % Do nothing.
            elseif strcmpi(propertyValue, 'true')
                propertyValue = true;
            elseif strcmpi(propertyValue, 'false')
                propertyValue = false;
            elseif all(isstrprop(propertyValue, 'digit'))
                propertyValue = str2double(propertyValue);
            end

            % Dynamically set the property on the cluster object
            c.AdditionalProperties.(propertyName) = propertyValue;
        end
    end
end

saveProfile(c);
parallel.defaultClusterProfile(clusterName);
fclose(fileID);

disp(['Profile cluster successfully created and name: ', clusterName]);