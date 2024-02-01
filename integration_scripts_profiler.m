function integration_scripts_profiler

% Get the release number.
versionOutput = version;
pattern = '\((.*?)\)';
tokens = regexp(versionOutput, pattern, 'tokens');

% Check if any parentheses were found for "version".
if ~isempty(tokens)
    versionNumber = tokens{1}{1}; % tokens is a cell array of cell arrays. Neat!
    versionNumber = versionNumber(2:end); % Remove the R since it's often already included in configuration files when using this environment variable.
    environmentVariableToSet = 'MATLAB_VERSION_STRING';
    setenv(environmentVariableToSet, versionNumber)
    versionNumberFloat = str2double(regexprep(versionNumber, '[ab]', ''));
    if ~isempty(strfind(versionNumber, 'b'))
        versionNumberFloat = versionNumberFloat + 0.5;
    end

    % The way that MATLAB handles numbers is infuriating.
    if versionNumberFloat > 2000
        versionNumberFloat = versionNumberFloat / 1000;
    end
else
    error('MATLAB release number could not be parsed. Exiting.');
end

if versionNumberFloat < 2012
    error('R2012a or newer is required to use this function.')
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

% Combine macOS and Linux.
isUnixBased = isunix || ismac;

% Open the .conf file for reading
fileID = fopen(confFileName, 'r');
if fileID == -1
    error('Failed to open .conf file: %s\n', confFileName);
end

try
    % Create the profile.
    clusterName = '';
    c = parallel.cluster.Generic;
    HasSharedFilesystem = false; % We'll change this if needed.

    % Set all general cluster profile properties by reading line by line BEFORE [AdditionalProperties] is found.
    while ~feof(fileID)
        line = fgetl(fileID);
        line = strtrim(line); % Trim whitespace from both ends of the line.

        if strcmp(line, '[AdditionalProperties]')
            break; % End general property processing and move onto AdditionalProperties.
        end

        % Ignore commented or blank lines.
        if ~isempty(line) && ~strncmp(line, '#', 1)
            parts = regexp(line, '=', 'split');
            if numel(parts) == 2
                propertyName = strtrim(parts{1});
                propertyValue = strtrim(parts{2});

                % Remove any double quotation marks from propertyValue.
                propertyValue = strrep(propertyValue, '"', '');

                % Get environment variables when used.
                if ~isempty(strfind(propertyValue, '$'))
                    pattern = '\$(\w+)';
                    tokens = regexp(propertyValue, pattern, 'tokens');

                    if ~isempty(tokens)
                        envVarName = tokens{1}{1};
                        envVarValue = getenv(envVarName);

                        % Replace the occurrence of the environment variable in the original string.
                        propertyValue = strrep(propertyValue, ['$' envVarName], envVarValue);
                    end
                end

                % Check for OS-specific properties.
                if ~isempty(strfind(propertyName, '(Windows)')) && ispc
                    propertyName = strrep(propertyName, '(Windows)', '');
                    propertyName = strtrim(propertyName);
                elseif ~isempty(strfind(propertyName, '(Unix)')) && isUnixBased
                    propertyName = strrep(propertyName, '(Unix)', '');
                    propertyName = strtrim(propertyName);
                elseif (strcmp(propertyName, 'JobStorageLocation.windows') && ispc) || (strcmp(propertyName, 'JobStorageLocation.unix') && ispc)                    
                 nextLine = fgetl(fileID);
                 eqIndex = strfind(nextLine, '=');
                                  
                 if ~isempty(eqIndex) % Check if the equals sign was found.
                    propertyValue2 = strtrim(nextLine(eqIndex+1:end));

                    % Swap values if 'windows' is not found in propertyName.
                    if ~isempty(strfind(lower(propertyName), 'windows'))
                        [propertyValue, propertyValue2] = deal(propertyValue2, propertyValue);
                    end

                    % Make JobStorageLocation a struct to properly save this.
                    propertyValueStruct = struct('windows', propertyValue, 'unix', propertyValue2);
                    c.JobStorageLocation = propertyValueStruct;
                    HasSharedFilesystem = true; % File contents take precedence over the file name.
                    continue
                else
                    error('The second line in JobStorageLocation struct does not contain an equals sign or is incorrectly formatted.');
                end

                elseif ~isempty(strfind(propertyName, '(Windows)')) || ~isempty(strfind(propertyName, '(Unix)'))
                    continue; % OS does not match, skip this property.
                end

                if strcmp(propertyName, 'Name')
                    if versionNumberFloat < 2.0165 && ~isempty(strfind(propertyValue, ' ')) % No spaces allowed prior to R2016b.ß
                        propertyValue = strrep(propertyValue, ' ', '_');
                    end

                    clusterName = propertyValue;
                    c.saveAsProfile(clusterName);
                    continue
                elseif ~isempty(strfind(propertyName, 'PluginScriptsLocation'))

                    if versionNumberFloat >= 2.017 && versionNumberFloat < 2.0195 % Change the name in a certain range of older releases.
                        propertyName = strrep(propertyName, 'PluginScriptsLocation', 'IntegrationScriptsLocation');
                    elseif versionNumberFloat < 2.017 % The pain we used to have to go through.
                        c.IndependentSubmitFcn = fullfile(propertyValue, 'independentSubmitFcn.m');
                        c.CommunicatingSubmitFcn = fullfile(propertyValue, 'communicatingSubmitFcn.m');                        
                        c.GetJobStateFcn = fullfile(propertyValue, 'getJobStateFcn.m');
                        c.DeleteJobFcn = fullfile(propertyValue, 'deleteJobFcn.m');
                        c.DeleteTaskFcn = fullfile(propertyValue, 'deleteTaskFcn.m');
                        c.CancelJobFcn = fullfile(propertyValue, 'cancelJobFcn.m');
                        c.CancelTaskFcn = fullfile(propertyValue, 'cancelTaskFcn.m');

                        continue % Change this to divide the files up, as they used to do this (yuck.)
                    end

                elseif strcmp(propertyName, 'JobStorageLocation') && ~isempty(strfind(propertyValue, 'struct'))
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
                elseif isempty(propertyValue)
                    % Do nothing because you gave nothing.
                elseif strcmpi(propertyValue, 'true') % Set booleans and doubles correctly.
                    propertyValue = true;
                elseif strcmpi(propertyValue, 'false')
                    propertyValue = false;
                elseif all(isstrprop(propertyValue, 'digit'))
                    propertyValue = str2double(propertyValue);
                end

                if strcmp(propertyName, 'RequiresOnlineLicensing') && versionNumberFloat < 2.017 && versionNumberFloat > 2.012
                    propertyName = 'RequiresMathWorksHostedLicensing';
                elseif strcmp(propertyName, 'RequiresOnlineLicensing') && versionNumberFloat < 2.0125 % You weren't around yet!
                    continue
                end
                
                % Temporarily store goodies in the cluster object.
                c.(propertyName) = propertyValue;
            end
        end
    end

    % Shared filesystem will be set by the filename, if it isn't set in the file's contents.
    if ~isempty(strfind(lower(confFileName), 'desktop.conf')) && HasSharedFilesystem == false
        c.HasSharedFilesystem = false;
    elseif ~isempty(strfind(lower(confFileName), 'cluster.conf')) || ~isempty(strfind(lower(confFileName), 'remote.conf')) || HasSharedFilesystem == true
        c.HasSharedFilesystem = true;
    end

    % There are no AdditionalProperties in R2016b and older.
    if versionNumberFloat > 2.017
        frewind(fileID); % Reset the file pointer to the beginning of the file before the second while loop. Otherwise, this whole section is ignored.
        inAdditionalPropertiesSection = false;

        % Set all AdditionalProperties by reading line by line after [AdditionalProperties] is found.
        while ~feof(fileID)
            line = fgetl(fileID);
            line = strtrim(line);

            if strcmp(line, '[AdditionalProperties]')
                inAdditionalPropertiesSection = true;
                continue; % Skip this line since we don't need to do anything else with it.
            end

            % Ignore commented or blank lines.
            if inAdditionalPropertiesSection && ~isempty(line) && ~strncmp(line, '#', 1)
                parts = regexp(line, '=', 'split');
                if numel(parts) == 2
                    propertyName = strtrim(parts{1});
                    propertyValue = strtrim(parts{2});
                    propertyValue = strrep(propertyValue, '"', '');

                    if ~isempty(strfind(propertyValue, '$'))
                        pattern = '\$(\w+)';
                        tokens = regexp(propertyValue, pattern, 'tokens');

                        if ~isempty(tokens)
                            envVarName = tokens{1}{1};
                            envVarValue = getenv(envVarName);
                            propertyValue = strrep(propertyValue, ['$' envVarName], envVarValue);
                        end
                    end

                    % Check for OS-specific properties.
                    if ~isempty(strfind(propertyName, '(Windows)')) && ispc
                        propertyName = strrep(propertyName, '(Windows)', '');
                        propertyName = strtrim(propertyName);
                    elseif ~isempty(strfind(propertyName, '(Unix)')) && isUnixBased
                        propertyName = strrep(propertyName, '(Unix)', '');
                        propertyName = strtrim(propertyName);
                    elseif ~isempty(strfind(propertyName, '(Windows)')) || ~isempty(strfind(propertyName, '(Unix)'))
                        continue;
                    end

                    % Set booleans and doubles correctly.
                    if isempty(propertyValue) % Do nothing.        
                    elseif strcmpi(propertyValue, 'true')
                        propertyValue = true;
                    elseif strcmpi(propertyValue, 'false')
                        propertyValue = false;
                    elseif all(isstrprop(propertyValue, 'digit'))
                        propertyValue = str2double(propertyValue);
                    end

                    c.AdditionalProperties.(propertyName) = propertyValue;                    
                end
            end
        end
    end
catch errorMessage
    if isempty(strfind(errorMessage.message, 'already exists.'))
        parallel.internal.ui.MatlabProfileManager.removeProfile(clusterName)
    end
    error('%s', errorMessage.message)
end

saveProfile(c);
parallel.defaultClusterProfile(clusterName);
fclose(fileID);

disp(['Profile cluster successfully created and name: ', clusterName]);