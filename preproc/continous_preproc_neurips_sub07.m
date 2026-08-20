%% TOC

%% Flags and constants
HP = 0.5; 
LP = 30;
HP_ica = 1;
LP_ica = 15;

%% paths and files
vp       = '07';
ftPath   = '../../../m-lib/fieldtrip/';
bidsPath = '../../bids/';

vhdr_tbl = struct2table(dir(fullfile(bidsPath, '**', ['sub-', vp, '*task-pedestrianNavigation_eeg.vhdr'])));
evts_tbl = struct2table(dir(fullfile(bidsPath, '**', ['sub-', vp, '*task-pedestrianNavigation_events.tsv'])));

eegfilebids    = fullfile(vhdr_tbl.folder, vhdr_tbl.name);
eventsfile     = fullfile(evts_tbl.folder, evts_tbl.name);
derivates_prefix  = fullfile(bidsPath, 'derivates', ['sub-', vp, '_task-pedestrianNavigation_']);

layoutFile    = 'EEG1010.lay';    % contained in fieldtrip template folder
elecsFile     = 'easycapM10.mat'; % contained in fieldtrip template folder

addpath(ftPath); ft_defaults;

%% filter continuous recording
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

% plot "New Segment" artefact at AFz (1)
new_segment = find(cfg2.event.original_sample == 1);
secs = 2;
% AFz = find(ismember('AFz', continuous_data.label));
% figure;
% for k = 1:numel(new_segment)
%     plot(continuous_data.trial{1}(AFz, new_segment(k):(new_segment(k)+secs*continuous_data.hdr.Fs)-1)); hold on;
% end
% figure; 
% for k = 1:numel(new_segment)
%     plot(cfg2.event.x_pos(new_segment(k):(new_segment(k)+secs*continuous_data.hdr.Fs)-1),  ...
%         cfg2.event.y_pos(new_segment(k):(new_segment(k)+secs*continuous_data.hdr.Fs)-1)); hold on;
% end

% pre-define artefact types: (1) New Segmemt, (2) door
% in databrowser, switch between artefacft types by clicking on colored field
% adjust "new Segment" artifact as appropriate
cfg.artfctdef.newsegment.artifact = [new_segment, (new_segment+secs*continuous_data.hdr.Fs)-1];
cfg.artfctdef.door.artifact   = zeros(0,2);
cfg.artfctdef.visual.artifact   = zeros(0,2);
arfct = ft_databrowser(cfg);

bad_channels = {'PO4'};

% write down segment with artefacts for later control plot
trial_with_arifacts = 205;
trl_of_artfct_trial = [trial_with_arifacts-1, trial_with_arifacts] .* cfg.blocksize .* continuous_data.hdr.Fs;
save(strcat(derivates_prefix, 'artifact_def.mat'), "arfct");


%% apply ICA
% filter the data
cfg = [];
cfg.lpfilter = 'yes';
cfg.lpfreq   = LP_ica;
cfg.hpfilter = 'yes';
cfg.hpfreq   = HP_ica;
cfg.demean           = 'yes';
ic_data = ft_preprocessing(cfg, continuous_data);

% remove artefacts
cfg = [];
cfg.artfctdef = arfct.artfctdef;
cfg.artfctdef.reject = 'partial';
ic_data = ft_rejectartifact(cfg, ic_data);

% run ica
cfg = [];
cfg.randomseed = 7; % set seed for replicable results
cfg.channel    = setdiff(ic_data.label, bad_channels);
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
cfgica = [];
cfgica.component  = [1]; 
ic_Corrected = ft_rejectcomponent(cfgica, ic, continuous_data);

% repair broken chan
elecM1    = ft_read_sens('template/electrode/easycap-M1.txt');
elecM1    = rmfield(elecM1, {'type', 'unit'});
label_idx = ismember(elecM1.label, continuous_data.label);
electmp  = structfun(@(x) x(find(label_idx),:), elecM1, 'UniformOutput', false);
[~, row_indx] = ismember(continuous_data.label, electmp.label); % make elec order as in data
elecOBCI  = structfun(@(x) x(row_indx,:), electmp, 'UniformOutput', false);
elecOBCI.type = 'eeg1010';
elecOBCI.unit = 'mm';
clear electmp elecM1

cfgrep            = [];
cfgrep.badchannel = bad_channels; 
cfgrep.elec       = elecOBCI;
cfgrep.method     = 'spline';
ic_Repaired        = ft_channelrepair(cfgrep, ic_Corrected);

% save
ic.bad_components = cfgica.component;
ic.bad_channels = bad_channels;
save(strcat(derivates_prefix, 'ic.mat'), "ic");

% % %% 4 identify door artefacts
% cfg = [];
% cfg.artfctdef.reject     = 'zero';
% cfg.artfctdef.newsegment = arfct.artfctdef.newsegment;
% ic_tmp = ft_rejectartifact(cfg, ic_Corrected);
% 
% plot(ismember(cfg2.event.label_abs_pos, {'door_0', 'door_1', 'door_2', 'door_3', 'door_4'}) & ...
%      ~startsWith(cfg2.event.session_name, 'wo')); 
% ylim([-1 2]);
% 
% cfg = [];
% cfg.artfctdef.zvalue.channel         = 'PO3';
% cfg.artfctdef.zvalue.cutoff          = 4.5;
% cfg.artfctdef.zvalue.interactive     = 'yes';
% cfg.artfctdef.zvalue.bpfilter        = 'yes';
% cfg.artfctdef.zvalue.bpfreq          = [10 30];
% cfg.artfctdef.zvalue.hilbert         = 'yes';
% cfg.artfctdef.zvalue.artfctpeak      = 'yes';
% cfg.artfctdef.zvalue.artfctpeakrange = [-.5 .5]; 
% cfg = ft_artifact_zvalue(cfg, ic_tmp);
% door_artifact_def = cfg.artfctdef.zvalue.artifact;
% 
% % use only first six
% door_artifact_def = door_artifact_def(1:6,:)
% 
% % 
% % %% apply DSS
% % % see https://www.fieldtriptoolbox.org/example/preproc/dss_ecg/
% cfg                   = [];
% cfg.method            = 'dss';
% cfg.dss.denf.function = 'denoise_avg2';
% cfg.dss.denf.params.artifact = door_artifact_def;
% cfg.dss.denf.params.demean   = true;
% cfg.dss.wdim          = 75;
% cfg.numcomponent      = 4;
% cfg.channel           = 'all';
% cfg.cellmode          = 'yes';
% dss = ft_componentanalysis(cfg, ic_tmp);
% 
% cfg = [];
% cfg.layout = layoutFile; % specify the layout file that should be used for plotting
% cfg.continuous = 'no';
% cfg.allowoverlap = 'yes';
% ft_databrowser(cfg, dss);
% 
% cfg           = [];
% cfg.component = [];  % too noisy, cannot identify artifact component
% dss_Corrected = ft_rejectcomponent(cfg, dss, ic_Corrected);
% 
% dss.bad_components = cfg.component;
% save(strcat(derivates_prefix, 'dss.mat'), "dss");
dss_Corrected = ic_Repaired;

%% plot trial with artifacts, pre and post cleaning
% eeg_precleaning  = ft_redefinetrial(cfg2, continuous_data); % see cfg2 above
% eeg_postcleaning = ft_redefinetrial(cfg2, dss_Corrected); % see cfg2 above
% trl_of_artfct_trial
% cfg = [];
% cfg.layout = layoutFile; % specify the layout file that should be used for plotting
% cfg.allowoverlap = 'yes';
% ft_databrowser(cfg, eeg_postcleaning);

h = plot(continuous_data.time{1}(trl_of_artfct_trial(1):trl_of_artfct_trial(2)), ...
[continuous_data.trial{1}(1,trl_of_artfct_trial(1):trl_of_artfct_trial(2)); ...
    dss_Corrected.trial{1}(1,trl_of_artfct_trial(1):trl_of_artfct_trial(2))]);
ylim([-150 75])
yticks(gca, [-100 0])
%yticklabels({'PO3', 'AFz'});
%h(3).Color = h(1).Color;
%h(4).Color = h(2).Color;
legend({'original', 'cleaned'});


%% check PO electrodes spectrogram
%eeg_postcleaning = ft_redefinetrial(cfg2, dss_Corrected);

cfg         = [];
cfg.method  = 'mtmfft';
cfg.taper   = 'hanning';
cfg.output  = 'pow';
cfg.pad     = 'nextpow2';
cfg.foilim  = [1 30];
cfg.channel = {'PO3', 'PO4', 'AFz'};
%powspctrm   = ft_freqanalysis(cfg, eeg_postcleaning);
powspctrm   = ft_freqanalysis(cfg, dss_Corrected);

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

% plot phase 
cfg = [];
cfg.bpfilter = 'yes';
cfg.bpfreq = [1 2]; 
cfg.hilbert = 'real';
cfg.channel    = {'PO3'};
bp_filt = ft_preprocessing(cfg, dss_Corrected);

%PO3 = find(ismember(dss_Corrected.label, 'PO3'));
subplot(1,4,4)
plot(bp_filt.time{1}(20001:21000), bp_filt.trial{1}(20001:21000));
ylim([-40 40]);
xlabel('Time (s)');
ylabel('Hilbert amplitude (\muV)');
title('Band-pass 1-2 Hz');
legend({'PO3'}); legend('BoxOff');

%exportgraphics(h, '../md_images/gaitcycle.png', 'Resolution', 300);

%% re-reference
% use REST reference:
% https://www.fieldtriptoolbox.org/example/preproc/rereference/#:~:text=We%20recommend%20the%20median%20reference,can%20be%20computed%20using%20ft_prepare_leadfield.
elecM1    = ft_read_sens('template/electrode/easycap-M1.txt');
elecM1    = rmfield(elecM1, {'type', 'unit'});
label_idx = ismember(elecM1.label, dss_Corrected.label);
electmp  = structfun(@(x) x(find(label_idx),:), elecM1, 'UniformOutput', false);
[~, row_indx] = ismember(dss_Corrected.label, electmp.label); % make elec order as in data
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

%eeg_epoched     = ft_preprocessing(cfg, eeg_postcleaning);
eeg_continuous  = ft_preprocessing(cfg, dss_Corrected);

%% save to BIDS derivates
%save([derivatespath, '_eeg_epoched.mat'], 'eeg_epoched');
%save([derivatespath, '_eeg_continuous.mat'], 'eeg_continuous');
%save([derivatespath, '_visual_artifact_def.mat'], 'visual_artifact_def');
%save([derivatespath, '_door_artifact_def.mat'], 'door_artifact_def');

hdr = ft_read_header(eegfilebids);
evt = ft_read_event(eegfilebids);
eeg = eeg_continuous.trial{1};
bvisionname = fullfile(bidsPath, 'derivates', ['sub-', vp, '-cleaned.vhdr']);
ft_write_data(bvisionname, eeg, 'dataformat', 'brainvision_eeg', 'header', hdr, 'event', evt);