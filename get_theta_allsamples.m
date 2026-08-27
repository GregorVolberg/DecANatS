function [] = get_theta_allsamples()

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
subjc = [1, 7]; % sub-01 (4 routes) and sub-07 (6 routes)
for vp = 1:numel(subjc)
    subj = subjc(vp);
    eegfilebids  = char(fullfile(bids_tbl.folder(subj), bids_tbl.name(subj)));
    eegfileclean = char(fullfile(clean_tbl.folder(subj), clean_tbl.name(subj)));
    arfct = importdata(char(fullfile(arfct_tbl.folder(subj), arfct_tbl.name(subj))));
    eventsfilebids = [eegfilebids(1:(end-8)), 'events.tsv'];

    evt = ft_read_tsv(eventsfilebids);
    sess_num = unique(evt.session_nr);
    for f = 1:numel(sess_num)
    smpl(f,1) = min(find(evt.session_nr == sess_num(f)));
    smpl(f,2) = max(find(evt.session_nr == sess_num(f)));
    end


    % % define segments; later select by "condition" (corner, door, null) and "turn" (left, right, straight)    
    % cfg                    = [];
    % cfg.trialfun           = 'ft_trialfun_bids_decanats'; % custom trialfun
    % cfg.trialdef.prestim   = 4.5; 
    % cfg.trialdef.poststim  = 4.5;
    % cfg.dataset            = eegfilebids;
    % cfg.representation     = 'table';
    % cfg = ft_definetrial(cfg);
    % 
    % % add artefact definition and reject artefacts
   %  cfg.artfctdef = arfct.artfctdef;
   %  cfg.artfctdef.reject = 'complete';
   % cfg = ft_rejectartifact(cfg);
    
    
    % preprocess
    cfgclean = [];
    cfgclean.dataset = eegfileclean;
    cfgclean.lpfilter = 'yes';
    cfgclean.lpfreq   = LP;
    cfgclean.hpfilter = 'yes';
    cfgclean.hpfreq   = HP;
    clean = ft_preprocessing(cfgclean);

    
    for act_sess = 1:size(smpl,1)
    cfg = [];
    cfg.latency = [clean.time{1}(smpl(act_sess, 1)), clean.time{1}(smpl(act_sess, 2))];
    tmp_clean = ft_selectdata(cfg, clean);

     % cfg = [];   
     % cfg.artfctdef = arfct.artfctdef;
     % cfg.artfctdef.reject = 'zero';
     % tmp_clean = ft_rejectartifact(cfg, tmp_clean);


    % TF analysis and baseline correction
    cfg            = [];
    cfg.output     = 'pow';
    cfg.method     = 'mtmconvol';
    cfg.taper      = 'hanning';
    cfg.keeptrials = 'yes';
    cfg.foi        = 4:1:7;
    cfg.pad        = 'nextpow2';
    cfg.t_ftimwin  = 7./cfg.foi;
    cfg.toi       = [tmp_clean.time{1}(1):1/250:tmp_clean.time{1}(end)];
    
    cut_time_points = arfct.artfctdef.newsegment.artifact(act_sess,:) - arfct.artfctdef.newsegment.artifact(act_sess,1) + 1;
    
    cfgb = [];
    cfgb.baseline  = [tmp_clean.time{1}(cut_time_points(2)), tmp_clean.time{1}(end)];
    cfgb.baselinetype = 'relchange';

    tf  = ft_freqbaseline(cfgb, ft_freqanalysis(cfg, tmp_clean));
    res = squeeze(mean(mean(tf.powspctrm, 3),2));
    res(cut_time_points(1):cut_time_points(2)) = NaN;
    allres{act_sess} = res;
end

%plot(allres{3})
theta_pow = cat(1,allres{:});

new_evts = [evt, table(theta_pow)];
%protocol.timestamp = cellstr(datetime(datetime(protocol.timestamp, 'ConvertFrom', 'posixtime'),...
                     %       'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z'''));
new_evts = new_evts(:,{'session_nr', 'session_name', 'timestamp', 'x_pos', 'y_pos', 'theta_pow'});
posixTime = posixtime(datetime(new_evts.timestamp, 'InputFormat', "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", 'TimeZone', 'UTC'));

news_evts = [table(posixTime), new_evts];
ft_write_tsv(['./preproc/', all_subs{subj}, '_thetapow.tsv'], new_evts);
end
end