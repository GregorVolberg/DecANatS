%% set bids path, ft path
bidsPath       = '../bids/';
preprocpath    = './preproc/';
ftPath         = '../../m-lib/fieldtrip/';
addpath(ftPath, preprocpath); ft_defaults;

%% get participant codes
tmp      = ft_read_tsv([bidsPath, 'participants.tsv']);
subjects = extractAfter(tmp.participant_id, 4); clear tmp
%subjects = sort(setdiff(subjects, {'S03', 'S06', 'S13'}));

for n = 1:numel(subjects)
%% construct individual file paths
vp             = subjects{n};
eegfilebids    = [bidsPath, 'sub-', vp, '/eeg/sub-', vp, '_task-wakeup_eeg.vhdr'];
eventsfile     = [bidsPath, 'sub-', vp, '/eeg/sub-', vp, '_task-wakeup_events.tsv'];
componentsfile = [bidsPath, 'derivates/independent_components_', vp, '.mat'];
% eegfilemat name definition see below

%% read events file
allevents        = readtable(eventsfile, 'FileType', 'text', 'Delimiter', '\t');
if ismember(allevents.bad_channels(1), 'n/a')
    bad_channels = [];
else
bad_channels     = strsplit(allevents.bad_channels{1}, ',');
end

if isnumeric(allevents.component_number)
    component_number = allevents.component_number(1);
else
    component_number = str2double(strsplit(allevents.component_number{1}, ','));
end

%% define trials
cfg = [];
cfg.trialfun           = 'ft_trialfun_bids_graspmi'; % custom trialfun, see ./preproc/ft_trialfun_bids_graspmi.m
cfg.trialdef.prestim   = 2.5; 
cfg.trialdef.poststim  = 5;
cfg.dataset            = eegfilebids;
cfg.representation     = 'table';
cfg.trialdef.movement         = {'forward', 'mouth', 'shoulder'};  % see template trialfuns in fieldtrip for syntax
cfg.trialdef.valid_movement   = {'yes'};  
cfg.trialdef.artefact_1stpass = 0;
cfg = ft_definetrial(cfg);

%% add pre-processing options to cfg and perform pre-processing
if ismember(allevents.bad_channels(1), 'n/a')
 cfg.channel   = {'all', '-VEOG', '-HEOG'}; 
else
 cfg.channel   = [{'all', '-VEOG', '-HEOG'}, strcat('-', bad_channels)]; 
end
cfg.demean    = 'yes';
cfg.hpfilter  = 'yes';
cfg.hpfreq    = 1;
cfg.lpfilter  = 'yes';
cfg.lpfreq    = 40;
preproc  = ft_preprocessing(cfg);
allelecs   = preproc.elec; % save field 'elec' for later
eegfilemat = [bidsPath, 'derivates/eeg_hp_', num2str(cfg.hpfreq), '_lp_', num2str(cfg.lpfreq), '_', vp, '.mat'];

%% same preprocessing with EOG channels
cfg.channel   = {'VEOG', 'HEOG'}; 
eogs = ft_preprocessing(cfg);

%% manually remove elec information for VEOG and HEOG from preprocessed data (interferes with ft_channelrepair)
EOG = ismember(preproc.elec.label, {'VEOG', 'HEOG'});
preproc.elec.label(EOG) = [];
preproc.elec.elecpos(EOG,:) = [];

%% if exists read components file, else perform component analyis
if isfile(componentsfile)
    ic = importdata(componentsfile);
else
    cfg = [];
    cfg.trialfun           = 'ft_trialfun_bids_graspmi'; % custom trialfun, see ./preproc/ft_trialfun_bids_graspmi.m
    cfg.trialdef.prestim   = 0.5; 
    cfg.trialdef.poststim  = 3;
    cfg.dataset            = eegfilebids;
    cfg.representation     = 'table';
    cfg.trialdef.movement         = {'forward', 'mouth', 'shoulder'};  % see template trialfuns in fieldtrip for syntax
    cfg.trialdef.valid_movement   = {'yes'};  
    cfg.trialdef.artefact_1stpass = 0;
    cfg = ft_definetrial(cfg);
    if ismember(allevents.bad_channels(1), 'n/a')
    cfg.channel   = {'all', '-VEOG', '-HEOG'}; 
    else
    cfg.channel   = [{'all', '-VEOG', '-HEOG'}, strcat('-', bad_channels)]; 
    end
    cfg.demean    = 'yes';
    cfg.hpfilter  = 'yes';
    cfg.hpfreq    = 1;
    cfg.lpfilter  = 'yes';
    cfg.lpfreq    = 40;
    preprocIC  = ft_preprocessing(cfg);

    cfg = [];
    cfg.randomseed = 7; % set seed for replicable results
    ic             = ft_componentanalysis(cfg, preprocIC);
end

%% reject components
cfg = [];
cfg.component  = component_number;
icCorrected    = ft_rejectcomponent(cfg, ic, preproc);

%% repair bad channels
cfg = [];
cfg.template = 'elec1010_neighb.mat'; % contain in fieldtrip template folder
cfg.method   = 'template';
neighb = ft_prepare_neighbours(cfg);

if ~isempty(bad_channels)
    cfgrep            = [];
    cfgrep.missingchannel = bad_channels; 
    cfgrep.neighbours     = neighb;
    cfgrep.method         = 'average';
    icRepaired        = ft_channelrepair(cfgrep, icCorrected);
    else
    icRepaired        = icCorrected;   
end

%% append EOG channels to EEG data
cfg = [];
cfg.keepsampleinfo = 'no';
eeg = ft_appenddata(cfg, icRepaired, eogs);
eeg.elec = allelecs;

%% remove trials with artifacts in 2nd pass
cfg = [];
cfg.trials = eeg.trialinfo.artefact_2ndpass == 0;
eeg = ft_selectdata(cfg, eeg);

%% save to bids/derivates/
save(eegfilemat, "eeg");

end

