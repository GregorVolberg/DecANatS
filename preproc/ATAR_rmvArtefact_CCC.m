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

%% z scoring and artifact peak detection
% format for DSS must be 3 column, [on, off, offset], eg [7590 7840 -125]
% for an artifact peak at 7715 and -+ 0.5 s around the peak
% z = (tmp(elec_indx,:) - mean(tmp(elec_indx,:))) ./ std(tmp(elec_indx,:));
% plot(z)

z_threshold = 6;
elec_indx   = 1; % 1: AFz; 8: PO4; 7: PO3
plusminus   = 0.5; % 0.5 sec um artefakt
offset      = plusminus * icCorrected.fsample;

artfc = nan(numel(icCorrected.trial),1);
for k = 1:numel(icCorrected.trial)
    tmp   = icCorrected.trial{k};
    ztmp  = zscore(tmp')';
    [zval, indx] = max(ztmp(elec_indx,:));
        if zval > z_threshold
            artfc(k)   = indx;
        end
end

seg_on   = icCorrected.sampleinfo(~isnan(artfc),1);
seg_off  = icCorrected.sampleinfo(~isnan(artfc),2);
art_peak = artfc(~isnan(artfc)) + seg_on;
art_on   = max(art_peak - offset, seg_on);
art_off  = min(art_on + offset, seg_off);
artfctm  = [art_on, art_off, repmat(-offset, numel(art_on), 1)]; % only works if peak +- offset is in seg

%% DSS
% see https://www.fieldtriptoolbox.org/example/preproc/dss_ecg/
params.artifact = artfctm;
params.demean = true;
cfg                   = [];
cfg.method            = 'dss';
cfg.dss.denf.function = 'denoise_avg2';
cfg.dss.denf.params   = params;
cfg.dss.wdim          = 75;
cfg.numcomponent      = 4;
cfg.channel           = 'all';
cfg.cellmode          = 'yes';
comp = ft_componentanalysis(cfg, icCorrected);

cfg = [];
cfg.layout = layoutFile; % specify the layout file that should be used for plotting
cfg.continuous = 'no';
cfg.allowoverlap = 'yes';
ft_databrowser(cfg, comp);

cfg           = [];
cfg.component = [1 2];
dssCorrected = ft_rejectcomponent(cfg, comp, icCorrected);

%% plot trial 4, pre and post cleaning
cfg = [];
cfg.layout = layoutFile; % specify the layout file that should be used for plotting
cfg.allowoverlap = 'yes';
ft_databrowser(cfg, dssCorrected);

h = plot(data.time{1}, [data.trial{4}(1,:);dssCorrected.trial{4}(1,:); ...
    data.trial{4}(7,:)/10-100;dssCorrected.trial{4}(7,:)/10-100]');
ylim([-150 75])
yticks(gca, [-100 0])
yticklabels({'PO3', 'AFz'});
h(3).Color = h(1).Color;
h(4).Color = h(2).Color;
legend({'original', 'cleaned'});

%% Option 2: partial rejection
% fill trial data with NaNs, or zeros, at the sample points that were
% identified for DSS (i.e., the artifact peak with surrounding 0.5s time
% window

cfg = [];
cfg.artfctdef.reject = 'nan';
cfg.artfctdef.zvalue.artifact = artfctm(:, 1:2)+75; %% check artfc-Definition!!
pr_data = ft_rejectartifact(cfg, icCorrected);

cfg = [];
cfg.layout = layoutFile; % specify the layout file that should be used for plotting
cfg.allowoverlap = 'yes';
ft_databrowser(cfg, pr_data);

%% Option 3: ATAR
% %% load bib spkit
% % see OpenProject Wiki for Details
% % prepare python spkit module to call from Matlab
terminate(pyenv); % to prevent conflicting pyenvs
pyenv('Version', ... 
            'C:\Users\LocalAdmin\Documents\spk\Scripts\python', ... 
            'ExecutionMode','OutOfProcess')
sp  = py.importlib.import_module('spkit');
np  = py.importlib.import_module('numpy');

xeeg = icCorrected;
for trl_idx = 1:numel(xeeg.trial)
    trl = xeeg.trial{trl_idx}';
    pyeeg      = np.array(trl);
    pyeegclean = sp.eeg.ATAR(pyeeg, wv = 'db8', verbose = 0, beta = 1, OptMode = 'soft', k1 = 10); 
    eegclean   = double(pyeegclean)';
    xeeg.trial{trl_idx} = eegclean;
end

% re-inspect data
cfg = [];
cfg.allowoverlap = 'yes';
ft_databrowser(cfg, xeeg);

h = plot(data.time{1}, [data.trial{4}(1,:); xeeg.trial{4}(1,:); ...
    data.trial{4}(7,:)/5-100; xeeg.trial{4}(7,:)/5-100]');
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
powspctrm   = ft_freqanalysis(cfg, dssCorrected);

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
label_idx = ismember(elecM1.label, dssCorrected.label);
electmp  = structfun(@(x) x(find(label_idx),:), elecM1, 'UniformOutput', false);
[~, row_indx] = ismember(dssCorrected.label, electmp.label); % make elec order as in data
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
dss  = ft_preprocessing(cfg, dssCorrected);
pr   = ft_preprocessing(cfg, pr_data);
xeeg = ft_preprocessing(cfg, xeeg);

%% save to BIDS derivates
save([derivatespath, '_atar.mat'], 'xeeg');
save([derivatespath, '_partreject.mat'], 'pr');
save([derivatespath, '_dss.mat'], 'dss');

%% have a look
% dat = importdata ([derivatespath, '_dss.mat']);
% cfg              = [];
% cfg.continuous   = 'no';
% cfg.layout       = layoutFile;
% cfg.allowoverlap = 'yes';
% ft_databrowser(cfg, dat);

%% need to adress the gait artifact (is introduced in all electrodes after re-referencing)
% - try IC on bandpass-filtered data