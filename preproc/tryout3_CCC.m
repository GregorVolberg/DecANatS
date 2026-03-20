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

%% read continuous data
cfg = [];
cfg.dataset            = eegfilebids;
cfg.channel   = 'all'; 
%cfg.demean    = 'yes';
cfg.hpfilter = 'yes';
cfg.hpfreq   = 1;
cfg.lpfilter = 'yes';
cfg.lpfreq   = 40;


cfg.trialfun           = 'ft_trialfun_bids'; % custom trialfun, see ./preproc/ft_trialfun_bids_graspmi.m
cfg.trialdef.prestim   = 4.5; 
cfg.trialdef.poststim  = 4.5;
cfg.dataset            = eegfilebids;
cfg.representation     = 'table';
%cfg.trialdef.ls_door   = {'door_1', 'door_2', 'door_3', 'door_4'};  % see template trialfuns in fieldtrip for syntax
%cfg.trialdef.valid_movement   = {'yes'};  
%cfg.trialdef.artefact_1stpass = 0;

cfg = ft_definetrial(cfg);
preproc = ft_preprocessing(cfg);


%% read in one long trial for rejection of segment onset artefacts
cfg          = [];
cfg.dataset  = eegfilebids;
cfg.hpfilter = 'yes';
cfg.hpfreq   = 1;
cfg.lpfilter = 'yes';
cfg.lpfreq   = 40;
%cfg.demean   = 'yes';
%cfg.trialdef.ntrials = 1;
cfg.trialdef.triallength = 5;
%cfg.trialfun           = 'ft_trialfun_bids'; % custom trialfun, see ./preproc/ft_trialfun_bids_graspmi.m
%cfg.trialdef.prestim   = 4.5; 
%cfg.trialdef.poststim  = 4.5;


%cfg.trialdef.triallength = 2;
cfg = ft_definetrial(cfg);

tmpdata = ft_preprocessing(cfg);

cfg.artfctdef.zvalue.channel         = 'Fz';
cfg.artfctdef.zvalue.cutoff          = 0.3;
cfg.artfctdef.zvalue.interactive     = 'yes';
cfg.artfctdef.zvalue.bpfilter        = 'yes';
cfg.artfctdef.zvalue.bpfreq          = [10 30];
cfg.artfctdef.zvalue.hilbert         = 'yes';
cfg.artfctdef.zvalue.artfctpeak      = 'yes';
cfg.artfctdef.zvalue.artfctpeakrange = [-0.5 0.5]; % remove out 0.5s prior and post peak
cfg = ft_artifact_zvalue(cfg);

% marked only the doors
params.artifact = cfg.artfctdef.zvalue.artifact;
params.demean = true;

% run DSS
cfg                   = [];
cfg.method            = 'dss';
cfg.dss.denf.function = 'denoise_avg2';
cfg.dss.denf.params   = params;
cfg.dss.wdim          = 75;
cfg.numcomponent      = 4;
cfg.channel           = 'all';
%cfg.cellmode          = 'yes';
comp = ft_componentanalysis(cfg, tmpdata);

% plot DSS
layoutFile = 'EEG1010.lay';    % contained in fieldtrip template folder
elecsFile  = 'easycapM10.mat'; % contained in fieldtrip template folder

cfg              = [];
cfg.viewmode     = 'component';
%cfg.continuous   = 'no';
cfg.layout       = layoutFile;
cfg.elec = elecsFile;
%cfg.allowoverlap = 'yes';
cfg.plotevents ='no';
ft_databrowser(cfg, comp);

cfg           = [];
cfg.component = [1 2];
meg_clean = ft_rejectcomponent(cfg, comp, tmpdata);

%% replace segment onset artefact with NANs
%cfg=[]
cfg = removefields(cfg, {'trl'});
cfg.artfctdef.reject = 'nan';
td2 = ft_rejectartifact(cfg, tmpdata);

%% re-stitch into one continuous recording
cfg = [];
cfg.continuous = 'yes';
td3 = ft_redefinetrial(cfg, td2);

%% segment into consecutive 5s-segments for DSS
cfg = [];
cfg.dataset  = eegfilebids;
cfg.hpfilter = 'yes';
cfg.hpfreq   = 1;
cfg.lpfilter = 'yes';
cfg.lpfreq   = 40;
cfg.trialdef.triallength = 5;
cfg = ft_definetrial(cfg);

tmpdata = ft_preprocessing(cfg, td3);

cfg.artfctdef.zvalue.channel         = 'Fz';
cfg.artfctdef.zvalue.cutoff          = 6;
cfg.artfctdef.zvalue.interactive     = 'yes';
cfg.artfctdef.zvalue.bpfilter        = 'yes';
cfg.artfctdef.zvalue.bpfreq          = [5 30];
cfg.artfctdef.zvalue.hilbert         = 'yes';
cfg.artfctdef.zvalue.artfctpeak      = 'yes';
cfg.artfctdef.zvalue.artfctpeakrange = [-1 1]; % remove out 1s prior and post peak
cfg = ft_artifact_zvalue(cfg);


acfg=cfg;


cfg=[]
cfg.continuous = 'yes'
cfg.artfctdef.zvalue.channel         = 'AFz';
cfg.artfctdef.zvalue.cutoff          = 6;
cfg.artfctdef.zvalue.interactive     = 'yes';
cfg.artfctdef.zvalue.bpfilter        = 'yes';
cfg.artfctdef.zvalue.bpfreq          = [5 30];
cfg.artfctdef.zvalue.hilbert         = 'yes';
cfg.artfctdef.zvalue.artfctpeak      = 'yes';
cfg.artfctdef.zvalue.artfctpeakrange = [-.25 .5]; % save out 250ms prior and 500ms post ECG peak
cfg = ft_artifact_zvalue(cfg, preproc);


%% define segments
cfg                    = [];
cfg.trialfun           = 'ft_trialfun_bids'; % custom trialfun, see ./preproc/ft_trialfun_bids_graspmi.m
cfg.trialdef.prestim   = 4.5; 
cfg.trialdef.poststim  = 4.5;
cfg.dataset            = eegfilebids;
cfg.representation     = 'table';
cfg.trialdef.ls_door   = {'door_1', 'door_2', 'door_3', 'door_4'};  % see template trialfuns in fieldtrip for syntax
%cfg.trialdef.valid_movement   = {'yes'};  
%cfg.trialdef.artefact_1stpass = 0;

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
trldefcfg = cfg;
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
cfgic.component  = [7];
icCorrected    = ft_rejectcomponent(cfgic, ic, data);


% plot z score at one elctrode
tmp       = icCorrected.trial{8};
elec_indx = 1; % 8: PO4; 7: PO3
z = (tmp(elec_indx,:) - mean(tmp(elec_indx,:))) ./ std(tmp(elec_indx,:));
plot(z)

%% try DSS
% https://www.fieldtriptoolbox.org/example/preproc/dss_ecg/
cfg=[]
cfg.continuous = 'no';
%cfg = removefields(cfg, {'channel', 'demean'});
cfg.artfctdef.zvalue.channel         = 'AFz';
cfg.artfctdef.zvalue.cutoff          = 4;
cfg.artfctdef.zvalue.interactive     = 'yes';
cfg.artfctdef.zvalue.bpfilter        = 'yes';
cfg.artfctdef.zvalue.bpfreq          = [8 20];
cfg.artfctdef.zvalue.hilbert         = 'yes';
cfg.artfctdef.zvalue.artfctpeak      = 'yes';
cfg.artfctdef.zvalue.artfctpeakrange = [-.2 .2]; % save out 200ms prior and post ECG peak
[cfg, artfct] = ft_artifact_zvalue(cfg, data);

cfg = trldefcfg;
cfg = removefields(cfg, {'channel', 'demean'});
cfg.artfctdef.zvalue.channel         = 'AFz';
cfg.artfctdef.zvalue.cutoff          = 2;
cfg.artfctdef.zvalue.interactive     = 'yes';
cfg.artfctdef.zvalue.bpfilter        = 'yes';
cfg.artfctdef.zvalue.bpfreq          = [5 30];
cfg.artfctdef.zvalue.hilbert         = 'yes';
cfg.artfctdef.zvalue.artfctpeak      = 'yes';
cfg.artfctdef.zvalue.artfctpeakrange = [-.25 .5]; % save out 250ms prior and 500ms post ECG peak
cfg = ft_artifact_zvalue(cfg);


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


