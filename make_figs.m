function [] = make_figs()


l_vs_null = sortrows(struct2table(dir('./md_images/l_corner_vs_null*.fig')), 'name');
r_vs_null = sortrows(struct2table(dir('./md_images/r_corner_vs_null*.fig')), 'name');
l_vs_r    = sortrows(struct2table(dir('./md_images/l_corner_vs_r_corner*.fig')), 'name');

% colormap for p-values
N = 256;
cmap = ones(N, 3); % Initialize white
idx_start = 1; %round(0.5*N); 
idx_mid   = round(1*N);
num_steps = idx_mid - idx_start + 1;
transition = linspace(1, 0, num_steps)';
cmap(idx_start:idx_mid, 2) = transition; % Green channel
cmap(idx_start:idx_mid, 3) = transition; % Blue channel

allFiles = {l_vs_null, r_vs_null, l_vs_r};
allFilesLabels = {'Left turn versus baseline', ...
    'right turn versus baseline', ...
    'Left turn versus right turn'};
for k = 1:numel(allFiles)
figFiles = allFiles{k};

order_of_files = [find(contains(figFiles.name, 'pos')); ...
find(contains(figFiles.name, 'opt')); ...
    find(contains(figFiles.name, 'head'))]; % pos, opt, head
figFiles = figFiles(order_of_files,:);
tile_labels = {'Position', 'Position', 'Optical Flow', 'Optical Flow', 'Head movement', 'Head movement'};
numFiles = height(figFiles);

newFig = figure;

set(gcf, 'Color', [1 1 1], 'Position', [100 100 479*1.5 317*2]);

t = tiledlayout(3, 2); % Automatically determines best grid (e.g., 2x2)

title(t, allFilesLabels{k}, 'FontSize', 14);


for i = 1:numFiles
    fname = fullfile(figFiles.folder(i), figFiles.name(i));
    hFig = openfig(char(fname), 'invisible');
    
    % Hauptachse finden (Colorbars/Legenden filtern)
    hAx = findall(hFig, 'type', 'axes', '-not', 'Tag', 'legend', '-not', 'Tag', 'Colorbar');
    
    if ~isempty(hAx)
        % 1. Ziel-Tile im neuen Layout aktivieren
        targetAx = nexttile(t, i);
        % 2. Inhalt der Achse (Linien, Surfaces etc.) in das Tile kopieren
        copyobj(hAx(1).Children, targetAx);
        
        % 3. Titel, Achsenbeschriftungen und Limits übertragen
        targetAx.XLim = hAx(1).XLim;
        targetAx.YLim = hAx(1).YLim;
        targetAx.ZLim = hAx(1).ZLim;
        
        if i == 1
            title(targetAx, ['accuracy']);
            
        elseif i == 2
            title(targetAx, 'p-value');
        else
            title(targetAx, '');
        end

        xlabel(targetAx, hAx(1).XLabel.String);
        ylabel(targetAx, hAx(1).YLabel.String);
        cb = colorbar;

        if mod(i,2) == 1
        targetAx.CLim = [0.3 0.7];
        title(targetAx, [tile_labels{i}, ': accuracy']);
        cb.Ticks = [0.3, 0.5, 0.7];                     % Locations of the ticks
        %cb.TickLabels = {'0.05', '0'}; % Custom text labels
        elseif mod(i,2) == 0
        title(targetAx, [tile_labels{i}, ': p-value']);
        targetAx.CLim = [0.95 1];
        cb.Ticks = [0.95, 1];                     % Locations of the ticks
        cb.TickLabels = {'0.05', '0'}; % Custom text labels
        colormap(targetAx, cmap);
        end

    end
    
    close(hFig);
end
savefig(newFig, ['./md_images/', erase(allFilesLabels{k}, whitespacePattern), '.fig']);
exportgraphics(newFig, ['./md_images/', erase(allFilesLabels{k}, whitespacePattern), '.png'], 'Resolution', 300);
close(newFig);
end

end