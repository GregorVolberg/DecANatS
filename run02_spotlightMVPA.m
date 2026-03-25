%% set bids path, ft path
bidsPath       = '../bids/';
preprocpath    = './preproc/';
cleanpath      = '../bids/derivates/';
ftPath         = '../../m-lib/fieldtrip/';
mvpath         = '../../m-lib/MVPA-Light/startup';

addpath(ftPath, preprocpath); ft_defaults;
addpath(mvpath); startup_MVPA_Light;

%% get participant codes
tmp      = ft_read_tsv([bidsPath, 'participants.tsv']);
subjects = extractAfter(tmp.participant_id, 4); clear tmp
%subjects = {'CCC'};

%% read cleaned files 
for n = 1:numel(subjects)
clean_all{n} = importdata([cleanpath, 'sub-', subjects{n}, '_task-actionDecoding_dss.mat']);
end

clean = clean_all{1};

%% TF analysis
cfg            = [];
cfg.output     = 'pow';
cfg.method     = 'mtmconvol';
cfg.taper      = 'hanning';
cfg.keeptrials = 'yes';
cfg.foi        = 4:1:30;
cfg.pad        = 'nextpow2';
cfg.t_ftimwin  = 7./cfg.foi;
cfg.toi        = -3:0.012:3.6;

cfgb = [];
cfgb.baseline  = [3 3.6];
cfgb.baselinetype = 'relchange';

cfg.trials     =  ismember(clean.trialinfo.landmark, 'door') & ...
                  ismember(clean.trialinfo.ls_door, {'door_1', 'door_2', 'door_3', 'door_4'});
doors = ft_freqanalysis(cfg, clean);
doors = ft_freqbaseline(cfgb, doors);

cfg.trials     =  ismember(clean.trialinfo.landmark, {'null'});
null = ft_freqanalysis(cfg, clean);
null = ft_freqbaseline(cfgb, null);

cfg.trials     =  ismember(clean.trialinfo.landmark, {'corner'});
corner = ft_freqanalysis(cfg, clean);
corner = ft_freqbaseline(cfgb, corner);

ndoors  = size(doors.powspctrm, 1); % 'rpt_chan_freq_time'
nnull   = size(null.powspctrm, 1);
ncorner = size(corner.powspctrm, 1);

%% MVPA
%https://www.fieldtriptoolbox.org/tutorial/stats/mvpa_light/
cfg = [] ;
cfg.method          = 'mvpa';
cfg.features        = 'chan';
cfg.latency         = [-3, 3];
cfg.design          = [ones(ndoors,1); 2*ones(nnull,1)];
cfg.mvpa.classifier = 'lda';
cfg.mvpa.hyperparameter = 'auto';
cfg.mvpa.metric     = 'accuracy'; % also try auc
cfg.mvpa.cv         = 'kfold';
cfg.mvpa.k          = 5;
%cfg.timwin          = 3; % smooth time bins
%cfg.freqwin         = 3; % smooth freq bins
stat = ft_freqstatistics(cfg, doors, null);

mv_plot_result(stat.mvpa, stat.time, stat.freq);
set(gcf, 'Color', [1 1 1], 'Position', [560 531 479 317]);
xlabel('Time (s)'); ylabel('Frequency (Hz)');
title('Classification: Doors vs. null');
exportgraphics(gcf, './md_images/door_vs_null_tfr.png', 'Resolution', 300);

cfg = [] ;
cfg.method          = 'mvpa';
cfg.features        = [];
cfg.latency         = [-0.5, -0.1];
cfg.frequency       = [8 10];
cfg.avgovertime = 'yes';
cfg.avgoverfreq = 'yes';
cfg.design          = [ones(ndoors,1); 2*ones(nnull,1)];
cfg.mvpa.classifier = 'lda';
cfg.mvpa.hyperparameter = 'auto';
cfg.mvpa.metric     = 'accuracy'; % also try auc
cfg.mvpa.cv         = 'kfold';
cfg.mvpa.k          = 5;

stat = ft_freqstatistics(cfg, doors, null);

layoutFile = 'EEG1010.lay';
cfg              = [];
cfg.parameter    = 'accuracy';
cfg.layout       = layoutFile;
cfg.colorbar     = 'yes';
cfg.zlim = [0.6 0.75];
ft_topoplotER(cfg, stat);
set(gcf, 'Color', [1 1 1], 'Position', [560 531 479 317]);
title('Doors vs. null, 9 Hz, -0.5 to -0.1 s');
exportgraphics(gcf, './md_images/door_vs_null_topo.png', 'Resolution', 300);

% corner versus null
cfg = [] ;
cfg.method          = 'mvpa';
cfg.features        = 'chan';
cfg.latency         = [-3, 3];
cfg.design          = [ones(ncorner,1); 2*ones(nnull,1)];
cfg.mvpa.classifier = 'lda';
cfg.mvpa.hyperparameter = 'auto';
cfg.mvpa.metric     = 'accuracy'; % also try auc
cfg.mvpa.cv         = 'kfold';
cfg.mvpa.k          = 5;
%cfg.timwin          = 3; % smooth time bins
%cfg.freqwin         = 3; % smooth freq bins
stat = ft_freqstatistics(cfg, corner, null);

mv_plot_result(stat.mvpa, stat.time, stat.freq);
set(gcf, 'Color', [1 1 1], 'Position', [560 531 479 317]);
xlabel('Time (s)'); ylabel('Frequency (Hz)');
title('Classification: Corners vs. null');
exportgraphics(gcf, './md_images/corners_vs_null_tfr.png', 'Resolution', 300);

cfg = [] ;
cfg.method          = 'mvpa';
cfg.features        = [];
cfg.latency         = [-0.5, -0.1];
cfg.frequency       = [8 10];
cfg.avgovertime = 'yes';
cfg.avgoverfreq = 'yes';
cfg.design          = [ones(ncorner,1); 2*ones(nnull,1)];
cfg.mvpa.classifier = 'lda';
cfg.mvpa.hyperparameter = 'auto';
cfg.mvpa.metric     = 'accuracy'; % also try auc
cfg.mvpa.cv         = 'kfold';
cfg.mvpa.k          = 5;

stat = ft_freqstatistics(cfg, corner, null);

layoutFile = 'EEG1010.lay';
cfg              = [];
cfg.parameter    = 'accuracy';
cfg.layout       = layoutFile;
cfg.colorbar     = 'yes';
cfg.zlim = [0.5 0.8];
ft_topoplotER(cfg, stat);
set(gcf, 'Color', [1 1 1], 'Position', [560 531 479 317]);
title('Corners vs. null, 9 Hz, -0.5 to -0.1 s');
exportgraphics(gcf, './md_images/corner_vs_null_topo.png', 'Resolution', 300);

