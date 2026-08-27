function [] = read_and_analyse_4()

%% set bids path, ft path
bidsPath       = '../bids/';
preprocpath    = './preproc/';
derivatespath  = '../bids/derivates/';
ftPath         = '../../m-lib/fieldtrip/';
mvpath         = '../../m-lib/MVPA-Light/startup';

fig_suffix = '_lda_neurips_head';

falpha = 0.05; % alpha for t-test

addpath(ftPath, preprocpath); ft_defaults;
addpath(mvpath); startup_MVPA_Light;

clean_tbl = struct2table(dir(fullfile(derivatespath, 'sub-*-cleaned.vhdr')));
bids_tbl  = struct2table(dir(fullfile(bidsPath, '**', 'sub-*task-pedestrianNavigation_eeg.vhdr')));
arfct_tbl = struct2table(dir(fullfile(derivatespath, 'sub-*_task-pedestrianNavigation_artifact_def.mat')));

if ~ all(strncmp(clean_tbl.name, bids_tbl.name, 6))
    error("\nOrder of cleaned and original data does not match.\n")
else
    fprintf("\nRead cleaned and original data:\n");
    all_subs = extractBefore(clean_tbl.name, 7);
    disp(table(all_subs, clean_tbl.name, bids_tbl.name, arfct_tbl.name, ...
        'VariableNames', {'participant', 'cleaned', 'original_bids', 'artefact_def'}));
end

%% Flags and constants
HP = 0.5; 
LP = 40;

%% subject loop
for subj = 1:numel(all_subs)

    eegfilebids  = char(fullfile(bids_tbl.folder(subj), bids_tbl.name(subj)));
    eegfileclean = char(fullfile(clean_tbl.folder(subj), clean_tbl.name(subj)));
    arfct = importdata(char(fullfile(arfct_tbl.folder(subj), arfct_tbl.name(subj))));

    % define segments; later select by "condition" (corner, door, null) and "turn" (left, right, straight)    
    cfg                    = [];
    cfg.trialfun           = 'ft_trialfun_bids_decanats_head'; % custom trialfun
    cfg.trialdef.prestim   = 4.5; 
    cfg.trialdef.poststim  = 4.5;
    cfg.dataset            = eegfilebids;
    cfg.representation     = 'table';
    cfg = ft_definetrial(cfg);
    
    % add artefact definition and reject artefacts
    cfg.artfctdef = arfct.artfctdef;
    cfg.artfctdef.reject = 'complete';
    cfg = ft_rejectartifact(cfg);
    
    
    % segment and preprocess
    cfgclean = [];
    cfgclean.trl = cfg.trl;
    cfgclean.dataset = eegfileclean;
    cfgclean.lpfilter = 'yes';
    cfgclean.lpfreq   = LP;
    cfgclean.hpfilter = 'yes';
    cfgclean.hpfreq   = HP;
    cfgclean.demean   = 'yes';
    clean = ft_preprocessing(cfgclean);

    % TF analysis and baseline correction
    cfg            = [];
    cfg.output     = 'pow';
    cfg.method     = 'mtmconvol';
    cfg.taper      = 'hanning';
    cfg.keeptrials = 'yes';
    cfg.foi        = 4:1:30;
    cfg.pad        = 'nextpow2';
    cfg.t_ftimwin  = 7./cfg.foi;
    cfg.toi        = -3:0.02:3.6;
    
    cfgb = [];
    cfgb.baseline  = [3 3.6];
    cfgb.baselinetype = 'relchange';

    tf{subj}  = ft_freqbaseline(cfgb, ft_freqanalysis(cfg, clean));

    % select trials per condition
    cfgsel = [];
    cfgsel.trials = ismember(tf{subj}.trialinfo.condition, 'door');
    door{subj} = ft_selectdata(cfgsel, tf{subj});
    cfgsel.trials = ismember(tf{subj}.trialinfo.condition, 'corner') & ismember(tf{subj}.trialinfo.turn, 'left');
    l_corner{subj} = ft_selectdata(cfgsel, tf{subj});
    cfgsel.trials = ismember(tf{subj}.trialinfo.condition, 'corner') & ismember(tf{subj}.trialinfo.turn, 'right');
    r_corner{subj} = ft_selectdata(cfgsel, tf{subj});
    cfgsel.trials = ismember(tf{subj}.trialinfo.condition, 'null');
    null{subj} = ft_selectdata(cfgsel, tf{subj});
end

%% MVPA statistics
% https://www.fieldtriptoolbox.org/tutorial/stats/mvpa_light/
cfg = [] ;
cfg.method          = 'mvpa';
cfg.features        = 'chan';
cfg.latency         = [-3, 3];
cfg.mvpa.classifier = 'lda';
cfg.mvpa.hyperparameter = 'auto';
cfg.mvpa.metric     = 'accuracy'; % also try auc
cfg.mvpa.cv         = 'kfold';
cfg.mvpa.k          = 5;
%cfg.timwin          = 3; % smooth time bins
%cfg.freqwin         = 3; % smooth freq bins


test_text    = {'door', 'l_corner', 'r_corner', 'l_corner'};
control_text = {'null', 'null', 'null', 'r_corner'};
test      = cellfun(@eval, test_text, 'UniformOutput', false);
control   = cellfun(@eval, control_text, 'UniformOutput', false);

% sub-07, nan present: exclude?
for stat_contrast = 1:numel(test)
    test_tf    = test{stat_contrast};
    control_tf = control{stat_contrast};
    for k = 1:numel(all_subs)
        ntest  = size(test_tf{k}.powspctrm, 1); % 'rpt_chan_freq_time'
        ncontrol   = size(control_tf{k}.powspctrm, 1);
        cfg.design          = [ones(ntest,1); 2*ones(ncontrol,1)];
        stat = ft_freqstatistics(cfg, test_tf{k}, control_tf{k});
        mv_results{k} = stat.mvpa; 
    end
    perf_all = cellfun(@(x) x.perf{1}, mv_results, 'UniformOutput', false);
    perf_all_array = permute(cat(3, perf_all{:}), [3,1,2]);
    [~, p, ~, t] = ttest(perf_all_array, 0.5, 'Tail', 'both', 'Alpha', falpha);
    mvr = mv_combine_results(mv_results, 'average');
    mv_plot_result(mvr, stat.time, stat.freq);
    clim(gca, [0.35 0.65]); 
    set(gcf, 'Color', [1 1 1], 'Position', [560 531 479 317]);
    xlabel('Time (s)'); ylabel('Frequency (Hz)');
    title(['Classification: ', test_text{stat_contrast}, ' vs. ' control_text{stat_contrast}]);
    exportgraphics(gcf, ['./md_images/', test_text{stat_contrast}, '_vs_', control_text{stat_contrast}, fig_suffix, '.png'], 'Resolution', 300);
    savefig(gcf, ['./md_images/', test_text{stat_contrast}, '_vs_', control_text{stat_contrast}, fig_suffix, '.fig']);
    close(gcf);

    N = 256;
    cmap = ones(N, 3); % Initialize entirely white [1, 1, 1]
    % Define index thresholds corresponding to 0.9, 0.95, and 1.0 scale
    idx_start = round(0.5*N); % White ends (index ~230)
    idx_mid   = round(1*N);%round(1 * N);    % Full Red starts (index ~243)
    num_steps = idx_mid - idx_start + 1;
    transition = linspace(1, 0, num_steps)';
    cmap(idx_start:idx_mid, 2) = transition; % Green channel
    cmap(idx_start:idx_mid, 3) = transition; % Blue channel

    mvr2 = mvr;
    mvr2.perf = {1-squeeze(p)};
    mv_plot_result(mvr2, stat.time, stat.freq);
    clim(gca, [0.9 1]); 
    colormap(cmap)
    set(gcf, 'Color', [1 1 1], 'Position', [560 531 479 317]);
    xlabel('Time (s)'); ylabel('Frequency (Hz)');
    title('');
    cb = colorbar;
    cb.Title.String = 'p-value';
    cb.Title.FontSize = 11;
    cb.Ticks = [0.9, 0.95, 1];                     % Locations of the ticks
    cb.TickLabels = {'0.1', '0.05', '0'}; % Custom text labels
    exportgraphics(gcf, ['./md_images/', test_text{stat_contrast}, '_vs_', control_text{stat_contrast},fig_suffix, '_p.png'], 'Resolution', 300);
    savefig(gcf, ['./md_images/', test_text{stat_contrast}, '_vs_', control_text{stat_contrast}, fig_suffix, '_p.fig']);
    close(gcf);

        N = 256;
    cmap2 = ones(N, 3); % Initialize entirely white [1, 1, 1]
    % Define index thresholds corresponding to 0.9, 0.95, and 1.0 scale
    idx_start = 1;%round(0.5*N); % White ends (index ~230)
    idx_mid   = round(1*N);%round(1 * N);    % Full Red starts (index ~243)
    num_steps = idx_mid - idx_start + 1;
    transition = linspace(1, 0, num_steps)';
    cmap2(idx_start:idx_mid, 2) = transition; % Green channel
    cmap2(idx_start:idx_mid, 3) = transition; % Blue channel

    mvr3 = mvr;
    mvr3.perf = {squeeze(t.tstat)};
    mv_plot_result(mvr3, stat.time, stat.freq);
    lower_t = tinv(1-falpha/2, t.df(1));
    upper_t = tinv(1-0.001/2, t.df(1));
    clim(gca, [lower_t upper_t]); 
    colormap(cmap2)
    set(gcf, 'Color', [1 1 1], 'Position', [560 531 479 317]);
    xlabel('Time (s)'); ylabel('Frequency (Hz)');
    title('');
    cb = colorbar;
    cb.Title.String = 't value';
    cb.Title.FontSize = 11;
    cb.Ticks = [2.5:1:4.5];                     % Locations of the ticks
    %cb.TickLabels = {'0.1', '0.05', '0'}; % Custom text labels
    exportgraphics(gcf, ['./md_images/', test_text{stat_contrast}, '_vs_', control_text{stat_contrast},fig_suffix, '_t.png'], 'Resolution', 300);
    savefig(gcf, ['./md_images/', test_text{stat_contrast}, '_vs_', control_text{stat_contrast}, fig_suffix, '_t.fig']);
    close(gcf);

end
end