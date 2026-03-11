%% paths and files
vp       = 'CCC';

ftPath   = '../../../m-lib/fieldtrip/';
bidsPath = '../../bids/';

eegfilebids     = [bidsPath, 'sub-', vp, '/eeg/sub-', vp, '_task-actionDecoding_eeg.vhdr'];
eventsfile      = [bidsPath, 'sub-', vp, '/eeg/sub-', vp, '_task-actionDecoding_events.tsv'];

derivatespath   = [bidsPath, 'derivates/', '/sub-', vp, '_task-actionDecoding'];
%badchannelsfile = ['bad_channels_', vp, '.tsv'];


%% set path
addpath(ftPath); ft_defaults;

%% define segments
cfg                    = [];
cfg.trialfun           = 'ft_trialfun_bids'; % custom trialfun, see ./preproc/ft_trialfun_bids_graspmi.m
cfg.trialdef.prestim   = 4.5; 
cfg.trialdef.poststim  = 4.5;
cfg.dataset            = eegfilebids;
cfg.representation     = 'table';

cfg = ft_definetrial(cfg);

%% add preprocessing options and databrowser options to cfg
cfg.lpfilter = 'yes';
cfg.lpfreq   = 30;
cfg.hpfilter = 'yes';
cfg.hpfreq   = 0.5;
cfg.continuous       = 'no';
cfg.channel          = 'all';
cfg.demean           = 'yes';
cfg.detrend          = 'yes';

%cfg = ft_preprocessing(cfg);

%cfg.allowoverlap = 'yes';
%cfg = ft_databrowser(cfg);

data = ft_preprocessing(cfg);

cfg.lpfilter = 'yes';
cfg.lpfreq   = 15;
cfg.hpfilter = 'yes';
cfg.hpfreq   = 1;
cfg.continuous       = 'no';
cfg.channel          = 'all';
cfg.demean           = 'yes';
cfg.detrend          = 'yes';

ic_data = ft_preprocessing(cfg);

layoutFile = 'EEG1010.lay';    % contained in fieldtrip template folder
elecsFile  = 'easycapM10.mat'; % contained in fieldtrip template folder

cfg = [];
cfg.randomseed = 7; % set seed for replicable results
ic             = ft_componentanalysis(cfg, ic_data);

cfg              = [];
cfg.viewmode     = 'component';
cfg.continuous   = 'no';
cfg.layout       = layoutFile;
cfg.allowoverlap = 'yes';
ft_databrowser(cfg, ic);

cfgic = [];
cfgic.component  = [1, 7];
icCorrected    = ft_rejectcomponent(cfgic, ic, data);

% https://www.fieldtriptoolbox.org/workshop/madrid2019/tutorial_cleaning/

cfg = [];
cfg.allowoverlap = 'yes';
artcfg = ft_databrowser(cfg, icCorrected);
articfg = rmfield(artcfg, 'trl');

articfg.artfctdef.reject = 'value';
articfg.artfctdef.value = nan;
d2 = ft_rejectartifact(articfg, icCorrected);

cfg =[];
cfg.method = 'linear';
d3 = ft_interpolatenan(cfg, d2);

cfg=[];
cfg.allowoverlap = 'yes';
ft_databrowser(cfg, d3);

%% ATAR
% %% load bib spkit
% % see OpenProject Wiki for Details
% % prepare python spkit module to call from Matlab
terminate(pyenv); % to prevent conflicting pyenvs
pyenv('Version', ... 
            'C:\Users\LocalAdmin\Documents\spk\Scripts\python', ... 
            'ExecutionMode','OutOfProcess')
sp  = py.importlib.import_module('spkit');
np  = py.importlib.import_module('numpy');


%% ATAR
xeeg = icCorrected;
%for idx = 1:numel(xeeg.trial)
trl_idx   = 4;
chan_idx = 7;
trl = xeeg.trial{trl_idx}';
chn = trl(:,chan_idx);
pyeeg      = np.array(chn);
pyeegF     = sp.filter_X(pyeeg,band=[0.5], btype='highpass',fs=250,verbose=0);
pyeegclean = sp.eeg.ATAR(pyeeg, winsize = 128*2, verbose = 0, beta = 0.6, OptMode = 'soft', k1 = 50); 
%pyeegF2    = sp.filter_X(pyeegclean,band=[30], btype='lowpass',fs=250,verbose=0);
eegclean   = double(pyeegclean)';
xeeg.trial{idx} = eegclean;
%end

plot(chn, 'r');
hold on;
plot(eegclean*3, 'b');

%% re-inspect data
cfg = [];
cfg.allowoverlap = 'yes';
ft_databrowser(cfg, xeeg);

%% re-reference
cfg            = [];
cfg.reref      = 'yes';
cfg.refchannel = 'all';
cfg.refmethod  = 'avg';
xeeg = ft_preprocessing(cfg, xeeg);

%% save to BIDS derivates
% 
save(derivatespath, 'xeeg');


