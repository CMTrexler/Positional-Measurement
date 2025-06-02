% Open a dialog box to select a folder with RotatedAndSubtracted Tiffs
folderPath = uigetdir('C:\', 'Select Folder Containing Rotated TIFF Files');

if isequal(folderPath, 0)
    disp('Folder selection canceled.');
    return;
else
    % Get a list of all TIFF files in the folder
    fileList = dir(fullfile(folderPath, '*.tiff'));
    
    % Optionally, include .tif extension:
    fileList = [fileList; dir(fullfile(folderPath, '*.tif'))];
    
    % Check image size
    % Create the full file path
    fileName = fullfile(folderPath, fileList(5).name); % chooses 5th image in folder
    img = imread(fileName);
    [rows, columns, ~] = size(img); % '~' ignores the third dimension (e.g., color channels)
    
    % Create prompts for selecting two points: each point has a row and a column.
    prompt = {...
        'Enter row for top left of ROI:', ...
        'Enter column for top left of ROI:', ...
        'Enter row for bottom right of ROI:', ...
        'Enter column for bottom right of ROI:'};
    dlgTitle = 'Input Matrix Points';
    dims = [1 35];
    
    % Suggest default values (e.g., top-left and bottom-right corners)
    defInputs = { '213', '147', '219', '245'};
    
    % Open the input dialog box
    matrixPointArray = inputdlg(prompt, dlgTitle, dims, defInputs);
    
    % Check if user canceled the dialog
    if isempty(matrixPointArray)
        disp('User cancelled.');
        return;
    end
    
    % Convert the answers from strings to numbers
    p1_row = str2double(matrixPointArray{1});
    p1_col = str2double(matrixPointArray{2});
    p2_row = str2double(matrixPointArray{3});
    p2_col = str2double(matrixPointArray{4});

    loopCount = 0;
    cellArray_averagedFrames = {};
    for k = 1:length(fileList)
        loopCount = loopCount + 1;

        % Read and process image, then calculate columnAverages
        fileName1 = fullfile(folderPath, fileList(k).name);
        img1 = imread(fileName1);
        croppedImage = img1(p1_row:p2_row, p1_col:p2_col);
        columnAverages = mean(croppedImage, 1);
        averagedFrames = columnAverages;

        % Normalize Array
        averagedFrames_min = min(averagedFrames);
        averagedFrames_max = max(averagedFrames);
        normalizedFrameIntensityArray = ((averagedFrames - averagedFrames_min) / (averagedFrames_max - averagedFrames_min));
                
        cellArray_averagedFrames{end+1} = normalizedFrameIntensityArray; 
    end

    % Create prompts for selecting two points: each point is a boundary for around fringes
    prompt = {...
        'Enter leftmost pixel of AOI that fully encompasses a fringe of interest + about 1/2 the distance to the next fringe:', ...
        'Enter rightmost pixel of AOI that fully encompasses a fringe of interest + about 1/2 the distance to the next fringe:'};
    dlgTitle = 'Input AOI Boundaries';
    dims = [1 35];
    
    % Suggest default values (e.g., top-left and bottom-right corners)
    defInputs = { '45', '105'};
    
    % Open the input dialog box
    boundaryArray = inputdlg(prompt, dlgTitle, dims, defInputs);
    
    % Check if user canceled the dialog
    if isempty(boundaryArray)
        disp('User cancelled.');
        return;
    end
    
    % Convert the answers from strings to numbers
    leftAOI_Boundary = str2double(boundaryArray{1});
    rightAOI_Boundary = str2double(boundaryArray{2});

    fringeLocationArray = [];
    loopCount = 0;
    for k = 1:length(cellArray_averagedFrames)
        pixelArray = 1:length(columnAverages);
        frameIntensityArray = cellArray_averagedFrames{k};
    
        % Cut plot array into a section
        IOI = zeroedFrameIntensityArray(leftAOI_Boundary:rightAOI_Boundary); % Intensity Values of Interest
        POI = pixelArray(leftAOI_Boundary:rightAOI_Boundary); % Pixels of Interest
    
        % Designate the most prominent peak in the section as the fringe of interest (FOI)
        [~ , locations, widths] = findpeaks(IOI, POI);
        [~, idx] = max(widths); % Finds the highest prominence value (not saved) and index of that value

        % Determine efficacy of frame. Prominence will be used to check,
        %   presence of only low prominence peaks means noisy frame
        if  isempty(max(widths))
            % Frame is too noisy, skip
            fprintf('Frame %d is too noisy and was skipped. \n', k)
            noisyFrameCount = noisyFrameCount + 1;
        else
            % Check if the indexed width is also the highest peak in a small
            %   region around it
            if loopCount == 311;
                keyboard;
            end
            halfAreaOfCheck = round((rightAOI_Boundary - leftAOI_Boundary) / 5);
            if (locations(idx) - halfAreaOfCheck) < 1
                checkPeakArray = frameIntensityArray(1: locations(idx) + halfAreaOfCheck);
                checkPixelArray = pixelArray(1: locations(idx) + halfAreaOfCheck);
            else
                checkPeakArray = frameIntensityArray(locations(idx) - halfAreaOfCheck: locations(idx) + halfAreaOfCheck);
                checkPixelArray = pixelArray(locations(idx) - halfAreaOfCheck: locations(idx) + halfAreaOfCheck);
            end
            if max(checkPixelArray) > rightAOI_Boundary
                % Peak outside AOI
                checkPixelArray = pixelArray(locations(idx) - halfAreaOfCheck: rightAOI_Boundary);
            end
            if min(checkPixelArray) < leftAOI_Boundary
                % Peak outside AOI
                checkPixelArray = pixelArray(leftAOI_Boundary: locations(idx) + halfAreaOfCheck);
            end

            % Fit Gaussian to fringe
            if (locations(idx) - round(widths(idx))) < 1
                FOI_Intensity = frameIntensityArray(1: locations(idx) + round(widths(idx))); % Build a new array holding only the FOI intensity
                FOI_Area = pixelArray(1: locations(idx) + round(widths(idx))); % build a new array holding the FOI x-values
            else
                FOI_Intensity = frameIntensityArray(locations(idx) - round(widths(idx)): locations(idx) + round(widths(idx))); % Build a new array holding only the FOI intensity
                FOI_Area = pixelArray(locations(idx) - round(widths(idx)): locations(idx) + round(widths(idx))); % build a new array holding the FOI x-values
            end
            gaussianFit = fittype('gauss1');
            [fittedResult, gof1] = fit(double(FOI_Area(:)), double(FOI_Intensity(:)), gaussianFit);
            fringeLocation = fittedResult.b1; % extracts the b value out of the Gaussian formula, b1 refers to a field contained in fittedResult

            fringeLocationArray = [fringeLocationArray, fringeLocation];
            loopCount = loopCount + 1;
        end
    end
    fringeLocationAvg = sum(fringeLocationArray) / numel(fringeLocationArray);
    greatestPositiveDeviationFromAvg = max(fringeLocationArray) - fringeLocationAvg;
    greatestNegativeDeviationFromAvg = fringeLocationAvg - min(fringeLocationArray);

    if greatestNegativeDeviationFromAvg > greatestPositiveDeviationFromAvg
        greatestDeviationFromAvg = greatestNegativeDeviationFromAvg;
    else
        greatestDeviationFromAvg = greatestPositiveDeviationFromAvg;
    end
    std = std(fringeLocationArray,1); % Divisor N. I assume this method can be considered an entire population

    % Open, write, and close results and inputs file
    [parentFolder, ~, ~] = fileparts(folderPath);
    fullFile = fullfile(parentFolder, 'StandardDeviation.txt');
    fid = fopen(fullFile, 'w');
    if fid == -1
        error('Could not open %s for writing.', fullFile);
    end
    fprintf(fid, 'Fringe Average Location = %.4f \n', fringeLocationAvg);
    fprintf(fid, 'Greatest Deviation From Average = %.4f \n', greatestDeviationFromAvg);
    fprintf(fid, 'Standard Deviation %.4f \n', std);
    fclose(fid);
end