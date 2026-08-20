%% set bids path, ft path
bidsPath       = '../bids/';
preprocpath    = './preproc/';
derivatespath  = '../bids/derivates/';
ftPath         = '../../m-lib/fieldtrip/';
mvpath         = '../../m-lib/MVPA-Light/startup';

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
    arfct = importdata(char(fullfile(arfct_tbl.folder(subj), arfct_tbl.name(subj))));

    % define segments; later select by "condition" (corner, door, null) and "turn" (left, right, straight)    
    cfg                    = [];
    cfg.trialfun           = 'ft_trialfun_bids_decanats'; % custom trialfun
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
    cfg.lpfilter = 'yes';
    cfg.lpfreq   = LP;
    cfg.hpfilter = 'yes';
    cfg.hpfreq   = HP;
    cfg.demean   = 'yes';
    clean = ft_preprocessing(cfg);

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


% ndoors  = size(door{1}.powspctrm, 1); % 'rpt_chan_freq_time'
% nnull   = size(null{1}.powspctrm, 1);
% cfg = [] ;
% cfg.method          = 'mvpa';
% cfg.features        = 'chan';
% cfg.latency         = [-3, 3];
% cfg.design          = [ones(ndoors,1); 2*ones(nnull,1)];
% cfg.mvpa.classifier = 'lda';
% cfg.mvpa.hyperparameter = 'auto';
% cfg.mvpa.metric     = 'accuracy'; % also try auc
% cfg.mvpa.cv         = 'kfold';
% cfg.mvpa.k          = 5;
% %cfg.timwin          = 3; % smooth time bins
% %cfg.freqwin         = 3; % smooth freq bins
% stat = ft_freqstatistics(cfg, door{1}, null{1});


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

for stat_contrast = 1:numel(test);
    test_tf    = test{stat_contrast};
    control_tf = control{stat_contrast};
    for k = 1:numel(all_subs)
        ntest  = size(test_tf{k}.powspctrm, 1); % 'rpt_chan_freq_time'
        ncontrol   = size(control_tf{k}.powspctrm, 1);
        cfg.design          = [ones(ntest,1); 2*ones(ncontrol,1)];
        stat = ft_freqstatistics(cfg, test_tf{k}, control_tf{k});
        mv_results{k} = stat.mvpa; 
    end
    mvr = mv_combine_results(mv_results, 'average');
    mv_plot_result(mvr, stat.time, stat.freq);
    clim(gca, [0.35 0.65]); 
    set(gcf, 'Color', [1 1 1], 'Position', [560 531 479 317]);
    xlabel('Time (s)'); ylabel('Frequency (Hz)');
    title(['Classification: ', test_text{stat_contrast}, ' vs. ' control_text{stat_contrast}]);
    exportgraphics(gcf, ['./md_images/', test_text{stat_contrast}, '_vs_', control_text{stat_contrast},'_lda_neurips.png'], 'Resolution', 300);
end

% 
% 
% cfg = [] ;
% cfg.method          = 'mvpa';
% cfg.features        = [];
% cfg.latency         = [-0.5, -0.1];
% cfg.frequency       = [8 10];
% cfg.avgovertime = 'yes';
% cfg.avgoverfreq = 'yes';
% cfg.design          = [ones(ndoors,1); 2*ones(nnull,1)];
% cfg.mvpa.classifier = 'lda';
% cfg.mvpa.hyperparameter = 'auto';
% cfg.mvpa.metric     = 'accuracy'; % also try auc
% cfg.mvpa.cv         = 'kfold';
% cfg.mvpa.k          = 5;
% 
% stat = ft_freqstatistics(cfg, doors, null);
% 
% layoutFile = 'EEG1010.lay';
% cfg              = [];
% cfg.parameter    = 'accuracy';
% cfg.layout       = layoutFile;
% cfg.colorbar     = 'yes';
% cfg.zlim = [0.6 0.75];
% ft_topoplotER(cfg, stat);
% set(gcf, 'Color', [1 1 1], 'Position', [560 531 479 317]);
% title('Doors vs. null, 9 Hz, -0.5 to -0.1 s');
% exportgraphics(gcf, './md_images/door_vs_null_topo.png', 'Resolution', 300);
% 
% % corner versus null
% cfg = [] ;
% cfg.method          = 'mvpa';
% cfg.features        = 'chan';
% cfg.latency         = [-3, 3];
% cfg.design          = [ones(ncorner,1); 2*ones(nnull,1)];
% cfg.mvpa.classifier = 'lda';
% cfg.mvpa.hyperparameter = 'auto';
% cfg.mvpa.metric     = 'accuracy'; % also try auc
% cfg.mvpa.cv         = 'kfold';
% cfg.mvpa.k          = 5;
% %cfg.timwin          = 3; % smooth time bins
% %cfg.freqwin         = 3; % smooth freq bins
% stat = ft_freqstatistics(cfg, corner, null);
% 
% mv_plot_result(stat.mvpa, stat.time, stat.freq);
% set(gcf, 'Color', [1 1 1], 'Position', [560 531 479 317]);
% xlabel('Time (s)'); ylabel('Frequency (Hz)');
% title('Classification: Corners vs. null');
% exportgraphics(gcf, './md_images/corners_vs_null_tfr.png', 'Resolution', 300);
% 
% cfg = [] ;
% cfg.method          = 'mvpa';
% cfg.features        = [];
% cfg.latency         = [-0.5, -0.1];
% cfg.frequency       = [8 10];
% cfg.avgovertime = 'yes';
% cfg.avgoverfreq = 'yes';
% cfg.design          = [ones(ncorner,1); 2*ones(nnull,1)];
% cfg.mvpa.classifier = 'lda';
% cfg.mvpa.hyperparameter = 'auto';
% cfg.mvpa.metric     = 'accuracy'; % also try auc
% cfg.mvpa.cv         = 'kfold';
% cfg.mvpa.k          = 5;
% 
% stat = ft_freqstatistics(cfg, corner, null);
% 
% layoutFile = 'EEG1010.lay';
% cfg              = [];
% cfg.parameter    = 'accuracy';
% cfg.layout       = layoutFile;
% cfg.colorbar     = 'yes';
% cfg.zlim = [0.5 0.8];
% ft_topoplotER(cfg, stat);
% set(gcf, 'Color', [1 1 1], 'Position', [560 531 479 317]);
% title('Corners vs. null, 9 Hz, -0.5 to -0.1 s');
% exportgraphics(gcf, './md_images/corner_vs_null_topo.png', 'Resolution', 300);
% 
