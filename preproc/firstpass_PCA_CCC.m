%% paths and files
vp       = 'CCC';

ftPath   = '../../../m-lib/fieldtrip/';
bidsPath = '../../bids/';

eegfilebids     = [bidsPath, 'sub-', vp, '/eeg/sub-', vp, '_task-actionDecoding_eeg.vhdr'];
eventsfile      = [bidsPath, 'sub-', vp, '/eeg/sub-', vp, '_task-actionDecoding_events.tsv'];

derivatespath   = [bidsPath, 'derivates/', '/sub-', vp, '_task-actionDecoding'];
%badchannelsfile = ['bad_channels_', vp, '.tsv'];

% %% load bib spkit
% % see OpenProject Wiki for Details
% % prepare python spkit module to call from Matlab
% terminate(pyenv); % to prevent conflicting pyenvs
% pyenv('Version', ... 
%             'C:\Users\LocalAdmin\Documents\spk\Scripts\python', ... 
%             'ExecutionMode','OutOfProcess')
% sp  = py.importlib.import_module('spkit');
% np  = py.importlib.import_module('numpy');

%% set path
addpath(ftPath); ft_defaults;

%% first read continuos data
% read data
cfg = [];
cfg.dataset            = eegfilebids;
cfg.channel   = 'all'; 
cfg.demean    = 'yes';
cfg.hpfilter = 'yes';
cfg.hpfreq   = 1;
cfg.lpfilter = 'yes';
cfg.lpfreq   = 40;
preproc = ft_preprocessing(cfg);

% read event
cfg                    = [];
cfg.trialfun           = 'ft_trialfun_bids'; 
cfg.trialdef.prestim   = 4.5; 
cfg.trialdef.poststim  = 4.5;
cfg.dataset            = eegfilebids;
cfg.representation     = 'table';
tmp = ft_definetrial(cfg);
evt_table = tmp.trl;

% plot z score at one elctrode
tmp       = preproc.trial{1};
elec_indx = 7; % 8: PO4; 7: PO3
z = (tmp(elec_indx,:) - mean(tmp(elec_indx,:))) ./ std(tmp(elec_indx,:));

plot(z); ylim([-1, 3]); xlabel('Sample'); ylabel('z Amplitude')
corner    = evt_table.begsample(ismember(evt_table.landmark,'corner'));
door      = evt_table.begsample(ismember(evt_table.landmark,'door'));
startstop = [0, 46511, 90665];
hold on;
scatter(door, zeros(length(door))+1, [], 'k', 'filled');
scatter(startstop, zeros(length(startstop))+1.5, [], 'r', "filled");
scatter(corner, zeros(length(corner))+2, [],'b', "filled");




%% manually remove elec information on VEOG and HEOG (interferes with ft_channelrepair)
    EOG = ismember(preproc.elec.label, {'VEOG', 'HEOG'});
    preproc.elec.label(EOG) = [];
    preproc.elec.elecpos(EOG,:) = [];

%% read bad channels
    bad_channels     = strsplit(events.bad_channels{1}, ','); 

    %% run ICA
    cfg = [];
    cfg.channel    = setdiff(preproc.elec.label, bad_channels);
    cfg.randomseed = 7; % set seed for replicable results
    ic             = ft_componentanalysis(cfg, preproc);

layoutFile = 'EEG1010.lay';    % contained in fieldtrip template folder
elecsFile  = 'easycapM10.mat'; % contained in fieldtrip template folder

cfg              = [];
cfg.viewmode     = 'component';
cfg.continuous   = 'no';
cfg.layout       = layoutFile;
cfg.allowoverlap = 'yes';
ft_databrowser(cfg, ic);
%% define segments
cfg                    = [];
cfg.trialfun           = 'ft_trialfun_bids'; 
cfg.trialdef.prestim   = 4.5; 
cfg.trialdef.poststim  = 4.5;
cfg.dataset            = eegfilebids;
cfg.representation     = 'table';

cfg = ft_definetrial(cfg);

%% add preprocessing options and databrowser options to cfg
cfg.lpfilter = 'yes';
cfg.lpfreq   = 40;
cfg.hpfilter = 'yes';
cfg.hpfreq   = 0.5;
cfg.continuous       = 'no';
cfg.channel          = 'all';
cfg.demean           = 'yes';
cfg.detrend          = 'yes';

%cfg = ft_preprocessing(cfg);

cfg.allowoverlap = 'yes';
cfg = ft_databrowser(cfg);

data = ft_preprocessing(cfg);

%??? replace with NAN, then interpolate NAN with ft_interpolateNAN
cfg=[]
cfg.artfctdef.reject = 'nan'
d2 = ft_rejectartifact(cfg, data);

ft_databrowser(cfg2);
cfg-
ft_rejectartifact(cfg)

eeg = ft_preprocessing(cfg);

%% inspect data
cfg = [];
cfg.allowoverlap = 'yes';
ft_databrowser(cfg, eeg);


layoutFile = 'EEG1010.lay';    % contained in fieldtrip template folder
elecsFile  = 'easycapM10.mat'; % contained in fieldtrip template folder

cfg = [];
cfg.randomseed = 7; % set seed for replicable results
ic             = ft_componentanalysis(cfg, eeg);

cfg              = [];
cfg.viewmode     = 'component';
cfg.continuous   = 'no';
cfg.layout       = layoutFile;
cfg.allowoverlap = 'yes';
ft_databrowser(cfg, ic);

% try ft_interpolatenan, in combination with rejectvisual
% https://www.fieldtriptoolbox.org/workshop/madrid2019/tutorial_cleaning/

%% ATAR
xeeg = eeg;
for idx = 1:numel(xeeg.trial)
pyeeg      = np.array(xeeg.trial{idx}');
pyeegclean = sp.eeg.ATAR(pyeeg, verbose = 0, OptMode = 'elim'); 
eegclean   = double(pyeegclean)';
xeeg.trial{idx} = eegclean;
end

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


