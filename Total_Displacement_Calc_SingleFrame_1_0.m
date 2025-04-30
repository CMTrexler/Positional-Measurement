laserWavelength = 632.816;

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

    % Calculate the spacing between fringes
    oneFringeFrameCount = 0;
    noisyFrameCount = 0;
    fringeSpacingArray = [];
    problemFrameArray = [];
    problemValueSpacingArray = [];

    % Create prompts for selecting two points: each point has a row and a column.
    prompt = {...
        'Enter leftmost pixel of AOI that fully encompasses the leftmost fringe:', ...
        'Enter rightmost pixel of AOI that fully encompasses the rightmost fringe:'};
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

    % Create prompts for selecting noise floor
    prompt = {'Enter noise floor:'};
    dlgTitle = 'Input Noise Floor';
    dims = [1 35];
    
    % Suggest default values (e.g., top-left and bottom-right corners)
    defInputs = { '0'};
    
    % Open the input dialog box
    noiseFloorCell = inputdlg(prompt, dlgTitle, dims, defInputs);
    
    % Check if user canceled the dialog
    if isempty(noiseFloorCell)
        disp('User cancelled.');
        return;
    end
    
    % Convert the answers from strings to numbers
    noiseFloor = str2double(noiseFloorCell{1});

    % Calculate distance between fringes
    badFitToNoisyCounter = 0;
    for k = 1:length(cellArray_averagedFrames)
        pixelArray = 1:length(columnAverages);
        frameIntensityArray = cellArray_averagedFrames{k};
    
        % Can be used to speed up data with noise floor
        zeroedFrameIntensityArray = frameIntensityArray;
        zeroedFrameIntensityArray(zeroedFrameIntensityArray < noiseFloor) = 0;
    
        % Cut plot array into a section
        IOI = zeroedFrameIntensityArray(leftAOI_Boundary:rightAOI_Boundary); % Intensity Values of Interest
        POI = pixelArray(leftAOI_Boundary:rightAOI_Boundary); % Pixels of Interest
    
        % Designate the most prominent peak in the section as the fringe of interest (FOI)
        [~ , locations, widths] = findpeaks(IOI, POI);
        [~, idx] = max(widths); % Finds the highest prominence value (not saved) and index of that value

        % Determine efficacy of frame. Prominence will be used to check,
        %   presence of only low prominence peaks means noisy frame
        if  isempty(max(widths)) || max(widths) < 4
            % Frame is too noisy, skip
            % fprintf('Frame %d is too noisy and was skipped. \n', k)
            noisyFrameCount = noisyFrameCount + 1;
        else
            % Check if the indexed width is also the highest peak in a small
            %   region around it
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
            centroidFringe1 = fittedResult.b1; % extracts the b value out of the Gaussian formula, b1 refers to a field contained in fittedResult
        
            % Find second most prominent peak in frame
            widths(idx) = 0; % Sets the width of previous found fringe to 0 so it is not found again
            if max(widths) > 3      % Checks if another fringe is available 
                firstFringeLocation = locations(idx);
                [~, idx] = max(widths); % Index other fringe
                secondFringeLocation = locations(idx);
                pixelSeperationOfFringes = abs(firstFringeLocation - secondFringeLocation);
                
                % Fit Gaussian to fringe
                FOI_Intensity = frameIntensityArray(locations(idx) - round(widths(idx)): locations(idx) + round(widths(idx))); % Build a new array holding only the FOI intensity
                FOI_Area = pixelArray(locations(idx) - round(widths(idx)): locations(idx) + round(widths(idx))); % build a new array holding the FOI x-values
                gaussianFit = fittype('gauss1');
                [fittedResult, gof2] = fit(double(FOI_Area(:)), double(FOI_Intensity(:)), gaussianFit);
                centroidFringe2 = fittedResult.b1;

                if gof1.rsquare < 0.7 || gof2.rsquare < 0.7
                    % Frame too noisy
                    badFitToNoisyCounter = badFitToNoisyCounter + 1;
                else
                    fringeSpacingFrame = abs(centroidFringe2 - centroidFringe1); % Calculate distance between fringes
                    if fringeSpacingFrame > 50 || fringeSpacingFrame < 10
                        fprintf('Check frame %d. \n', k)
                        problemFrameArray = [problemFrameArray, (k)];
                        problemValueSpacingArray = [problemValueSpacingArray, fringeSpacingFrame];
                    end
                    fringeSpacingArray = [fringeSpacingArray, fringeSpacingFrame];
                end
            else
                oneFringeFrameCount = oneFringeFrameCount + 1;
            end
        end
    end
    fringeSpacingAvg = sum(fringeSpacingArray) / length(fringeSpacingArray);

    pixelArray = 1:length(columnAverages); % Constant
    FOILocation = []; % Opening an empty array for appending, DEFUNCT

    frameIntensityArray = cellArray_averagedFrames{1};

    zeroedFrameIntensityArray = frameIntensityArray;
    zeroedFrameIntensityArray(zeroedFrameIntensityArray < 0.2) = 0; % Prevents vetting every peak and slowing data processing

    % Cut plot array into a section
    IOI = zeroedFrameIntensityArray(leftAOI_Boundary:rightAOI_Boundary); % Intensity Values of Interest
    POI = pixelArray(leftAOI_Boundary:rightAOI_Boundary); % Pixels of Interest

    % Designate the tallest and most prominent peak in the section as the fringe of interest (FOI)
    [peaks, locations, widths] = findpeaks(IOI, POI);
    [~, idx] = max(widths); % Finds the highest prominence value (not saved) and index of that value

    % Fit a Gaussian to the FOI
    FOI_Intensity = frameIntensityArray(locations(idx) - round(widths(idx)): locations(idx) + round(widths(idx))); % Build a new array holding only the FOI intensity
    FOI_Area = pixelArray(locations(idx) - round(widths(idx)): locations(idx) + round(widths(idx))); % build a new array holding the FOI x-values
    gaussianFit = fittype('gauss1');
    [fittedResult, gof] = fit(double(FOI_Area(:)), double(FOI_Intensity(:)), gaussianFit); % gof is "goodness-of-fit" contains r^2 and row vectors are converted to column vector 
                                                                       % (I dont know why this is necessary but the line-fit toolbox requires column vectors)
    % For Debugging
    %figure;
    %plot(fittedResult, FOI_Area, FOI_Intensity)
    
    % Append the centroid of the Gaussian to an array
    centroid = fittedResult.b1; % extracts the b value out of the Gaussian formula, b1 refers to a field contained in fittedResult
    FOILocation = [FOILocation, centroid];

    % Designate area around the peak program will search for the new
    %   location of the peak for the next frame
    searchAreaHalf = fringeSpacingAvg / 2; % Will search pixels to the left and right of the previous peak position
    
    fringeDisplacementArray = [];
    comparisonIssueFrameArray = [];
    % Iterate over multiple frames and save centoid position of FOI
    framesSkipped = 0;
    for k = 2:length(cellArray_averagedFrames)
        % Load next frames array data
        frameIntensityArray = cellArray_averagedFrames{k};

        % Set low intensity values to 0, elimination of peaks being found in noise
        frameIntensityArray(frameIntensityArray < 0.2) = 0;

        % Check for new higher prominence peaks, indicating a higher
        %   intensity frame is available for tracking
        % Cut array into large section AOI
        IOI = frameIntensityArray(leftAOI_Boundary:rightAOI_Boundary); % Intensity Values of Interest
        POI = pixelArray(leftAOI_Boundary:rightAOI_Boundary); % Pixels of Interest
        [newFringePeaks, newFringeLocations, newFringeWidths] = findpeaks(IOI, POI);

        % Designate the most prominent peak in the section as the fringe of interest (FOI)
        % Determine if the most prominent peak is related to last frames peak
        [~, newFringeIdx] = max(newFringePeaks); % Finds the highest prominence value (not saved) and index of that value

        % Determine efficacy of frame. Prominence will be used to check,
        %   presence of only low prominence peaks means noisy frame
        if  isempty(max(newFringeWidths)) || max(newFringeWidths) < 3.7 || max(newFringePeaks) < 0.95
            % Frame is too noisy, skip
            % fprintf('Frame %d is too noisy and was skipped. \n', k)
            framesSkipped = framesSkipped +1;
        else  
            if newFringeLocations(newFringeIdx) > (locations(idx) - searchAreaHalf) && newFringeLocations(newFringeIdx) < (locations(idx) + searchAreaHalf)
                % "New fringe" is just the old fringe translated
                % Update new fringe idx, locations, widths
                idx = newFringeIdx;
                locations = newFringeLocations;
                widths = newFringeWidths;
    
                % Save previous fringe data for comparison with new fringe data
                prevFringeCentroid = centroid;
    
                % Fit Gaussian to fringe
                if (locations(idx) - round(widths(idx))) < 1
                    FOI_Intensity = frameIntensityArray(1: locations(idx) + round(widths(idx))); % Build a new array holding only the FOI intensity
                    FOI_Area = pixelArray(1: locations(idx) + round(widths(idx))); % build a new array holding the FOI x-values
                else
                    FOI_Intensity = frameIntensityArray(locations(idx) - round(widths(idx)): locations(idx) + round(widths(idx))); % Build a new array holding only the FOI intensity
                    FOI_Area = pixelArray(locations(idx) - round(widths(idx)): locations(idx) + round(widths(idx))); % build a new array holding the FOI x-values
                end
                gaussianFit = fittype('gauss1');
                [fittedResult, gof] = fit(double(FOI_Area(:)), double(FOI_Intensity(:)), gaussianFit);
    
                % Calculate the distance between the previous frames centroid and
                %   the new centroid = movement of fringe >> movement of mirror
                centroid = fittedResult.b1;
                fringeDisplacement = centroid - prevFringeCentroid;
                fringeDisplacementArray = [fringeDisplacementArray, fringeDisplacement]; % Array will be summed later to evaluate total mirror movement
            else
                % Compare new fringe centroid to previous fringe
                %   centroid + or - the fringe spacing avg
                idx = newFringeIdx;
                locations = newFringeLocations;
                widths = newFringeWidths;
    
                % Save previous fringe data for comparison with new fringe data
                prevFringeCentroid = centroid;
    
                % Fit Gaussian to fringe
                FOI_Intensity = frameIntensityArray(locations(idx) - round(widths(idx)): locations(idx) + round(widths(idx))); % Build a new array holding only the FOI intensity
                FOI_Area = pixelArray(locations(idx) - round(widths(idx)): locations(idx) + round(widths(idx))); % build a new array holding the FOI x-values
                gaussianFit = fittype('gauss1');
                [fittedResult, gof] = fit(double(FOI_Area(:)), double(FOI_Intensity(:)), gaussianFit);
    
                % Calculate the distance between the previous frames centroid and
                %   the new centroid = movement of fringe >> movement of mirror
                centroid = fittedResult.b1;
                if prevFringeCentroid > centroid
                    fringeDisplacement = centroid - prevFringeCentroid + fringeSpacingAvg;
                else
                    fringeDisplacement = centroid - prevFringeCentroid - fringeSpacingAvg;
                end
                fringeDisplacementArray = [fringeDisplacementArray, fringeDisplacement]; % Array will be summed later to evaluate total mirror movement
            end
        end
    end

    % Open, write, and close results and inputs file
    [parentFolder, ~, ~] = fileparts(folderPath);
    fullFile = fullfile(parentFolder, 'Results.txt');
    fid = fopen(fullFile, 'w');
    if fid == -1
        error('Could not open %s for writing.', fullFile);
    end
    fprintf(fid, 'Total centroid movement = %.4f \n', sum(fringeDisplacementArray));
    fprintf(fid, 'Space between fringe average = %.4f \n', fringeSpacingAvg);
    fprintf(fid, 'Calculated mirror movement %.4f \n', (laserWavelength/fringeSpacingAvg/2) * sum(fringeDisplacementArray));
    fprintf(fid, 'Left AOI Boundary = %d \n', leftAOI_Boundary);
    fprintf(fid, 'Right AOI Boundary = %d \n', rightAOI_Boundary);
    fprintf(fid, 'Top Left Row = %d \n', str2double(matrixPointArray{1}));
    fprintf(fid, 'Top Left Column = %d \n', str2double(matrixPointArray{2}));
    fprintf(fid, 'Bottom Right Row = %d \n', str2double(matrixPointArray{3}));
    fprintf(fid, 'Bottom Right Column = %d \n', str2double(matrixPointArray{4}));
    fclose(fid);
end