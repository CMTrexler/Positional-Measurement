% Iterate rotation over all files in a folder
% Apply Image Subtraction
% Average columns of selected area and Save plots to selected folder

% Open a dialog box to select a folder with TIFF data set
folderPath = uigetdir('C:\', 'Select Folder Containing TIFF Files');

if isequal(folderPath, 0)
    disp('Folder selection canceled.');
    return;
end

% Get a list of all TIFF files in the folder
fileList = dir(fullfile(folderPath, '*.tiff'));

% Optionally, include .tif extension:
fileList = [fileList; dir(fullfile(folderPath, '*.tif'))];

% Choose a folder to save data to
outputFolder = uigetdir('C:\', 'Select Folder to Save Processed Data in');


if outputFolder == 0
    disp('User cancelled output folder selection.');
    return;
end

% Apply Image Subtraction

% Get a list of all TIFF files in the data folder
fileList = dir(fullfile(folderPath, '*.tiff'));

% Include .tif extension:
fileList = [fileList; dir(fullfile(folderPath, '*.tif'))];

% Create folder to contain subtracted tiff
folderName = 'Subtracted Tiffs';
mkdir(outputFolder, folderName);
subtractedSaveFileDir = fullfile(outputFolder, folderName);

% Automatically determine best frame to use for subtraction
% Looks for frame with best radial symmetry. Assumes the frame with best
%   symmetry has few fringe features
scoreArray = [];
for k = 1:length(fileList)
    if k == 13
        % keyboard;
    end
    % Create the full file path
    fileName = fullfile(folderPath, fileList(k).name);

    % Read/Open the image
    imgGaussianFitCheck = imread(fileName);

    % Edit image to only consider red channel
    redImgGaussianFitCheck = imgGaussianFitCheck(:,:,1);

    numAngles = 18; % Takes a sample every 18 degrees
    I   = im2double(redImgGaussianFitCheck);
    bw  = imbinarize(I, graythresh(I));  
    bw  = imfill(bw, 'holes');           % fill holes
    stats = regionprops(bw, 'Centroid','Area');
    [~,idx] = max([stats.Area]);
    center = stats(idx).Centroid;        % [x0, y0]

    [H, W] = size(I);
    x0 = center(1);  y0 = center(2);
  
    % Maximum radius you can sample without leaving image
    Rmax = floor(min([x0-1, y0-1, W-x0, H-y0]));
  
    thetas = linspace(0,2*pi,numAngles+1);
    thetas(end) = [];            % drop duplicate 2π
    sigma_r = zeros(Rmax,1);
    mean_r  = zeros(Rmax,1);
  
    for r = 1:Rmax
        % Sample points around the circle of radius r
        xs = x0 + r*cos(thetas);
        ys = y0 + r*sin(thetas);
    
        % Nilinear interp
        vals = interp2(I, xs, ys, 'linear', NaN);
    
        mean_r(r)  = mean(vals);
        sigma_r(r) = std(vals);
    end
  
    % Compute symmetry score
    score = 1 - sum(sigma_r) / (sum(mean_r) + eps);
    scoreArray = [scoreArray, score];
end

% Index best image for subtraction
[~, idx] = max(scoreArray);
fprintf('Frame chosen for subtraction is %d. \n', idx)
img = imread(fullfile(folderPath, fileList(idx).name));
subtractionImage = img(:,:,1);

% Subtract Images
% Loop over each file in the list
for k = 1:length(fileList)
    % Create the full file path
    fileName = fullfile(folderPath, fileList(k).name);

    % Read/Open the image
    img = imread(fileName);
    red_img = img(:,:,1); % Extracts only red channel
    subtractedImg = red_img - subtractionImage;

    % Change all negative values to 0
    subtractedImg(subtractedImg <0) = 0;

    % Convert to single so it matches BitsPerSample=32
    subtractedImg = single(subtractedImg);

    % Define an output filename (using the original name with a prefix)
    [~, name, ext] = fileparts(fileList(k).name);
    outFilename = fullfile(subtractedSaveFileDir, ['subtracted_' name ext]);

    % Save the subtracted image as a 32-bit float TIFF using the Tiff class
    t = Tiff(outFilename, 'w');
    tagstruct.ImageLength = size(subtractedImg, 1);
    tagstruct.ImageWidth  = size(subtractedImg, 2);
    tagstruct.Photometric = Tiff.Photometric.MinIsBlack;
    tagstruct.BitsPerSample = 32;
    tagstruct.SampleFormat = Tiff.SampleFormat.IEEEFP;  % IEEE floating point
    tagstruct.SamplesPerPixel = 1;  % For a single-channel image; adjust if multichannel
    tagstruct.Compression = Tiff.Compression.None;
    tagstruct.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
    t.setTag(tagstruct);
    t.write(subtractedImg);
    t.close();
end

% Rotate Images

% Get a list of all TIFF files in the folder
fileList = dir(fullfile(subtractedSaveFileDir, '*.tiff'));

% Optionally, include .tif extension:
fileList = [fileList; dir(fullfile(subtractedSaveFileDir, '*.tif'))];

% Create folder to contain rotated tiff
folderName = 'Rotated Tiffs';
mkdir(outputFolder, folderName);
rotatedSaveFileDir = fullfile(outputFolder, folderName);

% Rotate an image by X degrees
prompt = {'Enter Rotation Degrees:'};
dlg_title = 'Input';
num_lines = 1;
defaultans = {'-70'};

% Open the input dialog box
userInput = inputdlg(prompt, dlg_title, num_lines, defaultans);

% Check if the user pressed cancel or closed the dialog
if isempty(userInput)
    disp('User cancelled the input dialog.');
    return;
end

% The userInput is returned as a cell array; extract the first element
rotation = str2double(userInput{1});
disp(['Rotation Selected: ', num2str(rotation)]);

% Loop over each file in the list
for k = 1:length(fileList)
    % Create the full file path
    fileName = fullfile(subtractedSaveFileDir, fileList(k).name);

    % Read/Open the image
    img = imread(fileName);
    % Rotate Image
    rotatedImage = imrotate(img, rotation);

    % Define an output filename (using the original name with a prefix)
    [~, name, ext] = fileparts(fileList(k).name);
    outFilename = fullfile(rotatedSaveFileDir, ['rotated_' name ext]);

    % Save the roated image as a 32-bit float TIFF using the Tiff class
    t = Tiff(outFilename, 'w');
    tagstruct.ImageLength = size(rotatedImage, 1);
    tagstruct.ImageWidth  = size(rotatedImage, 2);
    tagstruct.Photometric = Tiff.Photometric.MinIsBlack;
    tagstruct.BitsPerSample = 32;
    tagstruct.SampleFormat = Tiff.SampleFormat.IEEEFP;  % IEEE floating point
    tagstruct.SamplesPerPixel = 1;  % For a single-channel image; adjust if multichannel
    tagstruct.Compression = Tiff.Compression.None;
    tagstruct.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
    t.setTag(tagstruct);
    t.write(rotatedImage);
    t.close();
end


        
% Average Columns of selected area to mimic ImageJ plot profile

% Get a list of all TIFF files in the folder
fileList = dir(fullfile(rotatedSaveFileDir, '*.tiff'));

% Optionally, include .tif extension:
fileList = [fileList; dir(fullfile(rotatedSaveFileDir, '*.tif'))];

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

% Create folder to contain subtracted tiff
folderName = 'Plots';
mkdir(outputFolder, folderName);
plotsSaveFileDir = fullfile(outputFolder, folderName);

% Create a figure once (invisible)
fig = figure('Visible', 'off');
ax = axes(fig);
lineHandle = plot(ax, nan, nan);  % Pre-create a line object with dummy data
xlabel(ax, 'Pixel');
ylabel(ax, 'Intensity');
title(ax, 'Plot of Intensity per Pixel');
grid on;
grid minor;

% Open, write, and close results and inputs file
fullFile = fullfile(outputFolder, 'ProcessInputs.txt');
fid = fopen(fullFile, 'w');
if fid == -1
    error('Could not open %s for writing.', fullFile);
end
fprintf(fid, 'Top Left Row = %d \n', str2double(matrixPointArray{1}));
fprintf(fid, 'Top Left Column = %d \n', str2double(matrixPointArray{2}));
fprintf(fid, 'Bottom Right Row = %d \n', str2double(matrixPointArray{3}));
fprintf(fid, 'Bottom Right Column = %d \n', str2double(matrixPointArray{4}));
fprintf(fid, 'Frame chosen for subtraction = %d \n', idx', str2double(matrixPointArray{4}));
fclose(fid);

% Loop over files and update the plot data
try
    for k = 1:length(fileList)
        % Read and process image, then calculate columnAverages
        fileName1 = fullfile(rotatedSaveFileDir, fileList(k).name);
        img1 = imread(fileName1);
        croppedImage = img1(p1_row:p2_row, p1_col:p2_col);
        columnAverages = mean(croppedImage, 1);
        averagedFrames = columnAverages;
        pixelArray = 1:length(columnAverages);

        % Normalize Array
        averagedFrames_min = min(averagedFrames);
        averagedFrames_max = max(averagedFrames);
        normalizedFrameIntensityArray = ((averagedFrames - averagedFrames_min) / (averagedFrames_max - averagedFrames_min));
        
        % Update the plot with new data
        set(lineHandle, 'XData', pixelArray, 'YData', normalizedFrameIntensityArray);
        drawnow;  % Ensure the updated data is rendered (may be optional)
        
        % Save the plot using print
        [~, name, ext] = fileparts(fileList(k).name);
        outFilename = fullfile(plotsSaveFileDir, ['plot_' name ext]);
        print(fig, outFilename, '-dpng', '-r300');
    end
catch ME
    % Close the figure once all files are processed
    close(fig);
    return
end
close(fig);
