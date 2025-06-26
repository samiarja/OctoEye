% Initialization
parent_folder = "/media/samiarja/USB/OctoEye_paper_dataset/";
parent_path = parent_folder+'imx-249-data/';
addpath("hex2rgb.m")

pixel_intensity_limit = 35;
feedback_range_array = 2800:1:3250;

folders = {'400','450','500','550','600','650','700','750','800','850','900','950','1000'};

colors = {'#610061','b','#00ff92','g','#ffbe00','r','#e90000','#a10000','#6d0000','#3b0f0f','#210808','#1c0404','#030000'};

% Feedback conversion parameters
feedback_min = 284;
feedback_max = 3965;
distance_at_min_mm = 92;
feedback_range = feedback_max - feedback_min;

% Preallocate cell arrays for storing data from each folder.
nFolders = numel(folders);
focal_mm_all = cell(1, nFolders);
peak_all     = cell(1, nFolders);
fileListAll  = cell(1, nFolders);
maxFileIndex = cell(1, nFolders);

feedback_motor_value = [];
frame_camera_hyperspectral_output = zeros(13,3);
vertCrop_half = 30;

% Peak analysis
for i = 1:nFolders
    currFolder = folders{i};
    fileList = readAndSortFileList(parent_path, currFolder);
    fileListAll{i} = fileList;
    nFiles = numel(fileList);

    peak_vals  = zeros(nFiles,1);

    for j = 1:nFiles
        img = imread(fullfile(parent_path, currFolder, fileList(j).name));
        peak_vals(j) = getPeakFromImage(img, pixel_intensity_limit);
    end

    [peak_val, idx_max] = max(peak_vals);
    maxFileIndex{i} = idx_max;
    peak_all{i} = peak_vals;

    selected_focal_length = str2double(fileList(idx_max).name(1:4));
    focal_length_mm = (feedback_max - selected_focal_length) / feedback_range * distance_at_min_mm;

    frame_camera_hyperspectral_output(i,:) = [str2double(folders{i}), focal_length_mm/10, peak_val];
    feedback_motor_value = [feedback_motor_value;feedback_range_array(idx_max)];
end

% Create a 12x12 figure using subtightplot.
figure(1001); clf;
set(gcf, 'Color', 'w');

% Subplot parameters for subtightplot:
gap    = [0.005 0.005];  % [vertical_gap, horizontal_gap]
marg_h = [0.02 0.02];    % [bottom_margin, top_margin]
marg_w = [0.02 0.02];    % [left_margin, right_margin]

ROI_size = 100; crop_radius = 35;

for row = 1:nFolders
    base_idx = maxFileIndex{row};

    for col = 1:nFolders
        currFolder = folders{col};
        fileList = fileListAll{col};
        fileIdx = min(base_idx, numel(fileList));

        fileList = readAndSortFileList(parent_path, currFolder);
        img = imread(fullfile(parent_path, currFolder, fileList(fileIdx).name));
        final_ROI = getFinalROI(img, pixel_intensity_limit, ROI_size, crop_radius);

        subplot_index = (row - 1) * nFolders + col;
        subtightplot(nFolders, nFolders, subplot_index, gap, marg_h, marg_w);
        imshow(imgaussfilt(final_ROI, 1), [0 pixel_intensity_limit]);

        if row == col
            hold on;
            rectangle('Position',[0.5, 0.5, size(final_ROI,2), size(final_ROI,1)], ...
                      'EdgeColor', colors{col}, 'LineWidth', 4);
            hold off;
        end
    end
end

% Focal distance vs wavelength plot
wavelength = double(frame_camera_hyperspectral_output(:,1));
optimal_focal = double(frame_camera_hyperspectral_output(:,2));
[sortedFocal, sortIdx] = sort(optimal_focal);
wavelength = wavelength(sortIdx);

hex_colors = {'#610061','#0000FF','#00ff92','#00FF00','#ffbe00','#FF0000',...
              '#e90000','#a10000','#6d0000','#3b0f0f','#210808','#1c0404','#030000'};

customRGB = cell2mat(cellfun(@hex2rgb, hex_colors, 'UniformOutput', false));
interp_colormap = generateInterpolatedColormap(wavelength, customRGB);

plotFocalDistanceTube(sortedFocal, wavelength, customRGB, interp_colormap);


function fileList = readAndSortFileList(parent_path, folder)
    fileList = dir(fullfile(parent_path, folder, '*.tiff'));
    numbers = cellfun(@(nm) str2double(regexp(nm, '\d+', 'match', 'once')), {fileList.name});
    [~, sortIdx] = sort(numbers);
    fileList = fileList(sortIdx);
end

function peak = getPeakFromImage(img, pixel_intensity_limit)
    if size(img,3) == 3, img = rgb2gray(img); end
    img(img > pixel_intensity_limit) = 0;
    rows = size(img,1);
    mid_row = round(rows/2);
    r_start = max(1, mid_row - 100);
    r_end = min(rows, mid_row + 50);
    cropped = double(img(r_start:r_end, :));
    cropped_blurred = imgaussfilt(cropped, 2);
    rowMaxima = max(cropped_blurred, [], 2);
    peak = max(rowMaxima);
end

function final_ROI = getFinalROI(img, pixel_intensity_limit, ROI_size, crop_radius)
    if size(img,3) == 3, img = rgb2gray(img); end
    img = double(img);
    [r, c] = size(img);
    center_y = round(r/2); center_x = round(c/2);
    ROI_half = ROI_size / 2;
    roi_y_min = max(1, center_y - ROI_half + 1); roi_y_max = min(r, center_y + ROI_half);
    roi_x_min = max(1, center_x - ROI_half + 1); roi_x_max = min(c, center_x + ROI_half);
    ROI_img = img(roi_y_min:roi_y_max, roi_x_min:roi_x_max);
    ROI_smoothed = imgaussfilt(ROI_img, 3);
    [~, idx_roi] = max(ROI_smoothed(:));
    [peak_y_roi, peak_x_roi] = ind2sub(size(ROI_smoothed), idx_roi);
    peak_y = roi_y_min - 1 + peak_y_roi;
    peak_x = roi_x_min - 1 + peak_x_roi;
    x_range = max(1, peak_x - crop_radius):min(c, peak_x + crop_radius);
    y_range = max(1, peak_y - crop_radius):min(r, peak_y + crop_radius);
    final_ROI = img(y_range, x_range);
    final_ROI(final_ROI < 0) = 0;
    final_ROI(final_ROI > pixel_intensity_limit) = pixel_intensity_limit;
end

function cmap = generateInterpolatedColormap(wavelengths, customRGB)
    xi = linspace(min(wavelengths), max(wavelengths), 256);
    cmap = zeros(256,3);
    for k = 1:3
        cmap(:,k) = interp1(wavelengths, customRGB(:,k), xi, 'linear');
    end
end

function plotFocalDistanceTube(sortedFocal, wavelength, customRGB, interp_colormap)
    figure(567567); clf; set(gcf, 'Color', 'w', 'Position', [100 100 850 900]); hold on;
    t_fine = linspace(min(sortedFocal), max(sortedFocal), 2000);
    w_fine = interp1(sortedFocal, wavelength, t_fine, 'linear'); 
    norm_w_fine = (w_fine - min(wavelength)) / (max(wavelength) - min(wavelength));
    dx = gradient(t_fine); dy = gradient(w_fine);
    L = sqrt(dx.^2 + dy.^2);
    nx = -dy ./ L; ny = dx ./ L;
    lineDiameter = 0.03; numCross = 15;
    offsets = linspace(-lineDiameter/2, lineDiameter/2, numCross);
    X = zeros(numCross, length(t_fine)); Y = zeros(numCross, length(t_fine));
    for i = 1:length(t_fine)
        X(:, i) = t_fine(i) + offsets' * nx(i);
        Y(:, i) = w_fine(i) + offsets' * ny(i);
    end
    C = repmat(norm_w_fine, numCross, 1);
    surf(X, Y, zeros(size(X)), C, 'EdgeColor', 'none', 'FaceColor', 'interp', 'FaceAlpha', 0.7);
    colormap(interp_colormap); shading interp;
    for i = 1:length(sortedFocal)
        scatter(sortedFocal(i), wavelength(i), 100, customRGB(i,:), 'filled', 'MarkerEdgeColor', 'k');
    end
    plot(sortedFocal, wavelength, '--k', 'LineWidth',2);
    yline(750, '--k', 'LineWidth', 2);
    set(gca, 'YDir', 'reverse', 'YTick', 400:50:1000, 'FontSize', 16, 'LineWidth', 3);
    xlabel({'Distance from sensor to ball lens surface (cm)', '(Focal distance)'}, 'FontSize', 18, 'FontWeight', 'bold');
    ylabel('Wavelength (nm)', 'FontSize', 18, 'FontWeight', 'bold');
    title("The change in focal distance with wavelength");
    text(2.28, 700, 'Visible light', 'FontSize', 24, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'left', 'Color', 'k', 'Rotation', 90);
    text(2.28, 950, 'Infrared', 'FontSize', 24, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'left', 'Color', 'k', 'Rotation', 90);
    grid on; hold off;
    xlim([2.26 2.625]); ylim([400 1000]);
end