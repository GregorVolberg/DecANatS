%% TOC
% 1 Visual artifact detection (segment onsets)
%   - read in continuous data (0.5-30 Hz)
%   - mark artefacts in databrowser
%   NO - overwrite artefacts with zeros
%
% 2 ICA for removing eye blink artefact
%   - filter data from (1) between 1 and 15 Hz
%   - remove artifacts from filtered data
%   - identify eye movement and blink component(s)
%   - remove component obtained in filtered data from data (1)
%
% 3 PCA for removing gait artefact
%   - apply PCA to data obtained after (2)
%   - remove gait component
%
%  4 

%% Flags and constants
HP = 0.5; 
LP = 30;
HP_ica = 1;
LP_ica = 15;

%% paths and files
vp       = 'CCC';

ftPath   = '../../../m-lib/fieldtrip/';
bidsPath = '../../bids/';

eegfilebids   = [bidsPath, 'sub-', vp, '/eeg/sub-', vp, '_task-actionDecoding_eeg.vhdr'];
eventsfile    = [bidsPath, 'sub-', vp, '/eeg/sub-', vp, '_task-actionDecoding_events.tsv'];
derivatespath = [bidsPath, 'derivates/', '/sub-', vp, '_task-actionDecoding'];

layoutFile    = 'EEG1010.lay';    % contained in fieldtrip template folder
elecsFile     = 'easycapM10.mat'; % contained in fieldtrip template folder

addpath(ftPath); ft_defaults;

%% filter continuous recording (-> "continuous_data")
% https://www.fieldtriptoolbox.org/tutorial/preproc/continuous/
cfg = [];
cfg.dataset  = eegfilebids;
cfg.lpfilter = 'yes';
cfg.lpfreq   = LP;
cfg.hpfilter = 'yes';
cfg.hpfreq   = HP;
continuous_data = ft_preprocessing(cfg);

%% visually inspect and mark artefacts
cfg = []; 
cfg.dataset  = eegfilebids;
cfg.preproc.lpfilter = 'yes';
cfg.preproc.lpfreq   = LP;
cfg.preproc.hpfilter = 'yes';
cfg.preproc.hpfreq   = HP;
cfg.blocksize = 5; % size of segments shown in databrowser

% ft_trialfun_general does not understand BIDS events, so call again with
% ft_trialfun_bids and copy event field to cfg
cfg2                    = [];
cfg2.trialfun           = 'ft_trialfun_bids'; 
cfg2.trialdef.prestim   = 4.5; 
cfg2.trialdef.poststim  = 4.5;
cfg2.dataset            = eegfilebids;
cfg2 = ft_definetrial(cfg2);
cfg.event = cfg2.event;

arfct = ft_databrowser(cfg);
visual_artifact_def = arfct.artfctdef.visual.artifact;

%% apply PCA
% use no further filtering fo rpCA
cfg = [];
cfg.artfctdef.reject = 'partial';
cfg.artfctdef.visual.artifact = visual_artifact_def;
pr_continuous = ft_rejectartifact(cfg, continuous_data);

cfg = [];
cfg.method     = 'pca';
pc             = ft_componentanalysis(cfg, pr_continuous);

cfg              = [];
cfg.viewmode     = 'component';
cfg.continuous   = 'yes';
cfg.blocksize = 5;
cfg.layout       = layoutFile;
ft_databrowser(cfg, pc);

cfgpca = [];
cfgpca.component  = 1;
pc_continuous = ft_rejectcomponent(cfgpca, pc, continuous_data);

%% apply ICA
% filter the data
cfg = [];
cfg.lpfilter = 'yes';
cfg.lpfreq   = LP_ica;
cfg.hpfilter = 'yes';
cfg.hpfreq   = HP_ica;
cfg.demean           = 'yes';
ic_data = ft_preprocessing(cfg, pc_continuous);

% remove artefacts
cfg = [];
cfg.artfctdef.reject = 'partial';
cfg.artfctdef.visual.artifact = visual_artifact_def;
ic_data = ft_rejectartifact(cfg, ic_data);

% run ica
cfg = [];
cfg.randomseed = 7; % set seed for replicable results
cfg.method     = 'runica';
ic             = ft_componentanalysis(cfg, ic_data);

% plot
cfg              = [];
cfg.viewmode     = 'component';
cfg.continuous   = 'yes';
cfg.blocksize = 5;
cfg.layout       = layoutFile;
ft_databrowser(cfg, ic);

% remove bad ic
cfgpca = [];
cfgpca.component  = 2;
ic_Corrected = ft_rejectcomponent(cfgpca, ic, pc_continuous);

% %% plot epochs
% eeg_epoched = ft_redefinetrial(cfg2, ic_Corrected); % see cfg2 above
% 
% cfg              = [];
% cfg.layout       = layoutFile;
% cfg.allowoverlap = 'yes';
% ft_databrowser(cfg, eeg_epoched);


%% 4 identify door artefact in epoched data
cfg = [];
cfg.artfctdef.reject = 'zero';
cfg.artfctdef.visual = visual_artifact_def; 
ic_tmp = ft_rejectartifact(cfg, ic_Corrected);

cfg = [];
cfg.artfctdef.zvalue.channel         = 'AFz';
cfg.artfctdef.zvalue.cutoff          = 6.5;
cfg.artfctdef.zvalue.interactive     = 'yes';
cfg.artfctdef.zvalue.bpfilter        = 'yes';
cfg.artfctdef.zvalue.bpfreq          = [10 30];
cfg.artfctdef.zvalue.hilbert         = 'yes';
cfg.artfctdef.zvalue.artfctpeak      = 'yes';
cfg.artfctdef.zvalue.artfctpeakrange = [-.5 .5]; 
cfg = ft_artifact_zvalue(cfg, ic_tmp);
door_artifact_def = cfg.artfctdef.zvalue.artifact;

%% apply DSS
% see https://www.fieldtriptoolbox.org/example/preproc/dss_ecg/
cfg                   = [];
cfg.method            = 'dss';
cfg.dss.denf.function = 'denoise_avg2';
cfg.dss.denf.params.artifact = door_artifact_def;
cfg.dss.denf.params.demean   = true;
cfg.dss.wdim          = 75;
cfg.numcomponent      = 4;
cfg.channel           = 'all';
cfg.cellmode          = 'yes';
dss = ft_componentanalysis(cfg, ic_tmp);

cfg = [];
cfg.layout = layoutFile; % specify the layout file that should be used for plotting
cfg.continuous = 'no';
cfg.allowoverlap = 'yes';
ft_databrowser(cfg, dss);

cfg           = [];
cfg.component = [1 2];
dss_Corrected = ft_rejectcomponent(cfg, dss, ic_Corrected);

%% plot trial 4, pre and post cleaning
eeg_precleaning  = ft_redefinetrial(cfg2, continuous_data); % see cfg2 above
eeg_postcleaning = ft_redefinetrial(cfg2, dss_Corrected); % see cfg2 above

cfg = [];
cfg.layout = layoutFile; % specify the layout file that should be used for plotting
cfg.allowoverlap = 'yes';
ft_databrowser(cfg, eeg_postcleaning);

h = plot(eeg_precleaning.time{1}, [eeg_precleaning.trial{4}(1,:); eeg_postcleaning.trial{4}(1,:); ...
    eeg_precleaning.trial{4}(7,:)/10-100; eeg_postcleaning.trial{4}(7,:)-100]');
ylim([-150 75])
yticks(gca, [-100 0])
yticklabels({'PO3', 'AFz'});
h(3).Color = h(1).Color;
h(4).Color = h(2).Color;
legend({'original', 'cleaned'});


%% check PO electrodes spectrogram
% my suspicion is that the left / right PO high amlitudes are artifacts
% from walking. The artifacts seems to be rhythmic, with a frequency in the typical gait cycle (~1.5 Hz), 
% and the artifacts have lower amplitudes when approaching doors (i.e. when reducing speed or stopping).

cfg         = [];
cfg.method  = 'mtmfft';
cfg.taper   = 'hanning';
cfg.output  = 'pow';
cfg.pad     = 'nextpow2';
cfg.foilim  = [1 30];
cfg.channel = {'PO3', 'PO4', 'AFz'};
powspctrm   = ft_freqanalysis(cfg, eeg_postcleaning);

h = figure;
set(h, 'Color', [1 1 1], 'Position', [248 589 1297 259]);
for k = 1:3
subplot(1,4,k);
plot(powspctrm.freq, powspctrm.powspctrm(k,:));
xlim([0,30]); 
xlabel('Frequency (Hz)');
ylabel('Power (\muV^2)');
title(powspctrm.label(k));
end

% plot phase at trial 4
cfg = [];
cfg.bpfilter = 'yes';
cfg.bpfreq = [1 2]; 
cfg.hilbert = 'real';
cfg.channel    = {'PO3', 'PO4'};
bp_filt = ft_preprocessing(cfg, dssCorrected);

subplot(1,4,4)
plot(bp_filt.time{1}, bp_filt.trial{4});
ylim([-40 40]);
xlabel('Time (s)');
ylabel('Hilbert amplitude (\muV)');
title('Trial 4, band-pass 1-2 Hz');
legend({'PO3', 'PO4'}); legend('BoxOff');

exportgraphics(h, '../md_images/gaitcycle.png', 'Resolution', 300);

%% re-reference
% use REST reference:
% https://www.fieldtriptoolbox.org/example/preproc/rereference/#:~:text=We%20recommend%20the%20median%20reference,can%20be%20computed%20using%20ft_prepare_leadfield.
elecM1    = ft_read_sens('template/electrode/easycap-M1.txt');
elecM1    = rmfield(elecM1, {'type', 'unit'});
label_idx = ismember(elecM1.label, eeg_postcleaning.label);
electmp  = structfun(@(x) x(find(label_idx),:), elecM1, 'UniformOutput', false);
[~, row_indx] = ismember(eeg_postcleaning.label, electmp.label); % make elec order as in data
elecOBCI  = structfun(@(x) x(row_indx,:), electmp, 'UniformOutput', false);
elecOBCI.type = 'eeg1010';
elecOBCI.unit = 'mm';
clear electmp elecM1

headmodel = []; sourcemodel = [];
headmodel.type = 'singlesphere';
headmodel.cond = [0.3300 1 0.0042 0.3300];  % conductivities of each sphere
headmodel.r = [71 72 79 85];                % radius of each sphere
headmodel.o = [0 0 0];
headmodel.unit = 'mm';

cfg = [];
cfg.headmodel = headmodel;
cfg.elec = elecOBCI;
cfg.method = 'basedonvol';
cfg.inwardshift = 20; % in mm, relative to the scalp surface which is at 85 mm radius
sourcemodel = ft_prepare_sourcemodel(cfg);

figure
ft_plot_headmodel(headmodel);
alpha 0.3
ft_plot_mesh(sourcemodel);
ft_plot_sens(elecOBCI, 'label', 'label', 'elecshape', 'disc');
view([80, 120, 20])

cfg = [];
cfg.headmodel = headmodel;
cfg.elec = elecOBCI;
cfg.sourcemodel = sourcemodel;
leadfield = ft_prepare_leadfield(cfg);

cfg             = [];
cfg.implicitref = [];
cfg.reref       = 'yes';
cfg.refmethod   = 'rest';
cfg.refchannel  = 'all';
cfg.leadfield   = leadfield;
eeg_epoched     = ft_preprocessing(cfg, eeg_postcleaning);
eeg_continuous  = dss_Corrected;

%% save to BIDS derivates
save([derivatespath, '_eeg_epoched.mat'], 'eeg_epoched');
save([derivatespath, '_eeg_continuous.mat'], 'eeg_continuous');
save([derivatespath, '_visual_artifact_def.mat'], 'visual_artifact_def');
save([derivatespath, '_door_artifact_def.mat'], 'door_artifact_def');

