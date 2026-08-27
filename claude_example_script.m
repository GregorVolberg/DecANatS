%% EEG-CORRELATES-OF-TURNING: TIME-DOMAIN + DISTANCE-DOMAIN (ARC-LENGTH) ANALYSIS
%
% Pipeline overview
% ------------------
% 1. Load BIDS EEG data + Motion-BIDS position data (x_pos, y_pos) for one participant
% 2. Load corner coordinates (route metadata) and detect closest-approach events per corner
% 3. Epoch EEG around each corner event (-3 to +3 s) with ft_definetrial/ft_preprocessing
% 4. Time-frequency decomposition per trial (ft_freqanalysis, keeptrials = 'yes')
%    -> power stays in REAL TIME/Hz here, this part is untouched by resampling
% 5. For each trial, compute cumulative ARC LENGTH (walked path length) from x_pos/y_pos,
%    re-referenced so 0 m = corner event
% 6. Interpolate each trial's power (per channel/freq) from its own (uneven) distance axis
%    onto a COMMON distance grid (-3 to +3 m) -> spatially-normalized power
% 7. Repeat across participants/corners, grand-average, plot
%
% Assumes: FieldTrip on path (ft_defaults already called), Motion-BIDS-style layout:
%   sub-01/eeg/sub-01_task-walk_eeg.<ext>  (+ _channels.tsv, _events.tsv)
%   sub-01/motion/sub-01_task-walk_tracksys-imu_motion.tsv (+ _motion.json, _channels.tsv)
%   task metadata: corners.tsv with columns: corner_id, x, y   (route geometry, in meters)
%
% Adjust file names / channel labels / paths to match your actual dataset.
% 
% **The core trick (step 6)** is per-trial: take the trial's `x_pos`/`y_pos` samples, compute cumulative arc length, shift it so 0 m = the corner event, then `interp1` each trial's power values from its own (uneven) distance axis onto one shared `dist_grid`. That's the "resampling," but it happens on the already-computed power (from `ft_freqanalysis` in real time/Hz), not on raw voltage — this avoids ambiguity about what frequency means under a nonlinearly warped time axis.
% 
% **Design choices flagged in the comments you should sanity-check:**
% - I baseline-correct in the time domain (fixed pre-corner *time* window) before warping to distance, since a fixed time window is more comparable across trials than a fixed distance window walked at different speeds.
% - Outside the walked range, I return `NaN` rather than extrapolating (`interp1(...,'linear', NaN)`), so a very slow walker's -3 m point that a fast walker didn't reach in real time doesn't get invented data.
% - `unique(dist_rel,'stable')` handles pauses/backtracking that would otherwise break `interp1`'s monotonicity requirement — trials with too few clean points get skipped with a warning.
% 
% **What you'll need to adapt:** file paths/extensions, actual Motion-BIDS channel names, and how corner coordinates and left/right turn direction are stored in your dataset (I assumed a `corners.tsv` in `stimuli/` and split results by `corner_id` — you'll likely want to split by turn direction instead/additionally for your left-vs-right contrast).
% 

close all; clear; clc
ft_defaults

%% ------------------------------------------------------------------
%% 0. CONFIG
%% ------------------------------------------------------------------

bids_root   = '/path/to/bids_root';
sub_label   = 'sub-01';
task_label  = 'walk';

pre_window  = -3;    % s, time-domain epoch start
post_window =  3;    % s, time-domain epoch end
dist_pre    = -3;    % m, distance-domain window start
dist_post   =  3;    % m, distance-domain window end
dist_step   =  0.02; % m, resolution of common distance grid
dist_grid   = dist_pre:dist_step:dist_post;   % common x-axis for ALL trials/participants

radius_m    = 1.5;   % m, "closest approach" search radius around each corner (see step 2)

%% ------------------------------------------------------------------
%% 1. LOAD EEG DATA (BIDS)
%% ------------------------------------------------------------------

eeg_dir  = fullfile(bids_root, sub_label, 'eeg');
eeg_file = fullfile(eeg_dir, sprintf('%s_task-%s_eeg.vhdr', sub_label, task_label)); % adapt extension

cfg           = [];
cfg.dataset   = eeg_file;
hdr           = ft_read_header(cfg.dataset);
fs_eeg        = hdr.Fs;   % should be 250 Hz per your setup

%% ------------------------------------------------------------------
%% 2. LOAD MOTION DATA (Motion-BIDS) AND CORNER COORDINATES
%% ------------------------------------------------------------------

motion_dir   = fullfile(bids_root, sub_label, 'motion');
motion_file  = fullfile(motion_dir, sprintf('%s_task-%s_tracksys-imu_motion.tsv', sub_label, task_label));
motion_chan  = fullfile(motion_dir, sprintf('%s_task-%s_tracksys-imu_channels.tsv', sub_label, task_label));

motion_tbl   = readtable(motion_file, 'FileType', 'text', 'Delimiter', '\t');
chan_tbl     = readtable(motion_chan, 'FileType', 'text', 'Delimiter', '\t');

% Motion-BIDS tsv usually has NO header row -> columns follow order in channels.tsv.
% If yours already has headers x_pos / y_pos, skip this renaming block.
if ~any(strcmpi(motion_tbl.Properties.VariableNames, 'x_pos'))
    motion_tbl.Properties.VariableNames = chan_tbl.name';
end

x_pos  = motion_tbl.x_pos;
y_pos  = motion_tbl.y_pos;
fs_mot = 250; % Hz, read from *_motion.json ("SamplingFrequency") in practice

% Corner coordinates (route geometry) - one row per corner, reused across all trials
corners_tbl = readtable(fullfile(bids_root, 'stimuli', 'corners.tsv'), ...
                         'FileType', 'text', 'Delimiter', '\t');
% expects columns: corner_id (e.g. 'corner_0'), x, y

%% ------------------------------------------------------------------
%% 3. DETECT CLOSEST-APPROACH SAMPLE PER CORNER (TIME-LOCKING EVENT)
%% ------------------------------------------------------------------
% For each corner, find the walking sample nearest that corner's coordinate,
% restricted to a reasonable search radius so you don't grab a distant pass-by.

n_corners = height(corners_tbl);
event_samples = nan(n_corners,1);   % sample index (in motion_tbl / at fs_mot) of closest approach

for c = 1:n_corners
    cx = corners_tbl.x(c);
    cy = corners_tbl.y(c);
    d  = sqrt((x_pos - cx).^2 + (y_pos - cy).^2);
    within_radius = d < radius_m;
    if ~any(within_radius)
        warning('Participant never came within %.1f m of %s - skipping', radius_m, corners_tbl.corner_id{c});
        continue
    end
    idx_candidates = find(within_radius);
    [~, min_idx]    = min(d(idx_candidates));
    event_samples(c) = idx_candidates(min_idx);
end

% Convert motion-sample event indices to EEG-sample indices / seconds.
% If EEG and motion streams are already synchronized and share fs, this is direct;
% otherwise use your sync offset here.
assert(fs_mot == fs_eeg, 'Resample motion or EEG so sampling rates match, or align via timestamps.');
event_samples_eeg = event_samples; % same indexing assumed after sync

%% ------------------------------------------------------------------
%% 4. DEFINE + PREPROCESS EEG TRIALS AROUND EACH CORNER EVENT
%% ------------------------------------------------------------------

trl = [];
for c = 1:n_corners
    if isnan(event_samples_eeg(c)); continue; end
    begsample = round(event_samples_eeg(c) + pre_window  * fs_eeg);
    endsample = round(event_samples_eeg(c) + post_window * fs_eeg);
    offset    = round(pre_window * fs_eeg);  % samples before trigger, negative
    trl(end+1,:) = [begsample, endsample, offset, c]; %#ok<SAGROW> % last col = corner index, custom
end

cfg              = [];
cfg.dataset      = eeg_file;
cfg.trl          = trl(:,1:3);
cfg.demean       = 'yes';
cfg.baselinewindow = [-3 -2.5];  % adjust to a period free of movement artifact if possible
cfg.bpfilter     = 'yes';
cfg.bpfreq       = [1 40];
data_epoched     = ft_preprocessing(cfg);

corner_idx_per_trial = trl(:,4);  % keep track of which corner each trial belongs to

%% ------------------------------------------------------------------
%% 5. TIME-FREQUENCY DECOMPOSITION (STAYS IN REAL TIME/Hz)
%% ------------------------------------------------------------------

cfg              = [];
cfg.method       = 'wavelet';
cfg.width        = 5;
cfg.output       = 'pow';
cfg.foi          = 2:1:40;
cfg.toi          = pre_window:1/fs_eeg:post_window;   % keep full sample resolution for interpolation
cfg.keeptrials   = 'yes';
tfr              = ft_freqanalysis(cfg, data_epoched);
% tfr.powspctrm: [trials x channels x freq x time]

%% ------------------------------------------------------------------
%% 6. PER-TRIAL ARC LENGTH -> DISTANCE-RELATIVE AXIS
%% ------------------------------------------------------------------

n_trials = size(tfr.powspctrm, 1);
n_chan   = size(tfr.powspctrm, 2);
n_freq   = size(tfr.powspctrm, 3);
n_time   = size(tfr.powspctrm, 4);

powspctrm_dist = nan(n_trials, n_chan, n_freq, numel(dist_grid));

for tr = 1:n_trials

    begsample = trl(tr,1);
    endsample = trl(tr,2);

    x_trial = x_pos(begsample:endsample);
    y_trial = y_pos(begsample:endsample);

    dx = diff(x_trial);
    dy = diff(y_trial);
    step_dist = sqrt(dx.^2 + dy.^2);
    cum_dist  = [0; cumsum(step_dist)];         % arc length from trial start

    % re-reference so 0 m = corner event (event sample sits at -pre_window*fs_eeg into the trial)
    event_sample_in_trial = round(-pre_window * fs_eeg) + 1;
    dist_rel = cum_dist - cum_dist(event_sample_in_trial);

    % enforce strict monotonicity (guards against pauses/backtracking near the corner)
    [dist_rel_unique, unique_idx] = unique(dist_rel, 'stable');
    if numel(dist_rel_unique) < 5
        warning('Trial %d: not enough monotonic samples, skipping distance interpolation', tr);
        continue
    end

    for ch = 1:n_chan
        for f = 1:n_freq
            power_time = squeeze(tfr.powspctrm(tr, ch, f, :));
            power_time_unique = power_time(unique_idx);

            powspctrm_dist(tr, ch, f, :) = interp1( ...
                dist_rel_unique, power_time_unique, dist_grid, ...
                'linear', NaN);   % NaN outside the walked range, rather than extrapolating blindly
        end
    end
end

%% ------------------------------------------------------------------
%% 7. AVERAGE ACROSS TRIALS (THIS PARTICIPANT), PER CORNER OR COLLAPSED
%% ------------------------------------------------------------------

% Collapsed across all corners for this participant:
pow_dist_avg = squeeze(nanmean(powspctrm_dist, 1));  % [chan x freq x dist]

% Per corner (e.g. compare corner_0 vs corner_1 if they differ in turn direction):
unique_corners = unique(corner_idx_per_trial);
pow_dist_by_corner = struct();
for c = unique_corners'
    trial_mask = corner_idx_per_trial == c;
    pow_dist_by_corner.(corners_tbl.corner_id{c}) = ...
        squeeze(nanmean(powspctrm_dist(trial_mask,:,:,:), 1));
end

%% ------------------------------------------------------------------
%% 8. SAVE PARTICIPANT-LEVEL RESULT (for later grand-averaging across subjects)
%% ------------------------------------------------------------------

out_dir = fullfile(bids_root, 'derivatives', 'distance_realigned', sub_label);
if ~exist(out_dir, 'dir'); mkdir(out_dir); end

result           = [];
result.dist_grid = dist_grid;
result.freq      = tfr.freq;
result.label     = tfr.label;
result.pow_dist_avg      = pow_dist_avg;
result.pow_dist_by_corner = pow_dist_by_corner;
save(fullfile(out_dir, sprintf('%s_task-%s_distpow.mat', sub_label, task_label)), 'result');

%% ------------------------------------------------------------------
%% 9. QUICK PLOT: ONE CHANNEL, TIME-FREQUENCY-AS-DISTANCE
%% ------------------------------------------------------------------

chan_to_plot = 'Cz';   % adapt to a channel present in tfr.label
chan_idx     = find(strcmpi(tfr.label, chan_to_plot));

if ~isempty(chan_idx)
    figure;
    imagesc(dist_grid, tfr.freq, squeeze(pow_dist_avg(chan_idx,:,:)));
    axis xy;
    xlabel('Distance to corner (m)');
    ylabel('Frequency (Hz)');
    title(sprintf('%s - %s - power aligned to distance-to-corner', sub_label, chan_to_plot));
    xline(0, 'w--', 'LineWidth', 1.5);   % corner event
    colorbar;
end

%% ------------------------------------------------------------------
%% NOTES / THINGS TO ADAPT
%% ------------------------------------------------------------------
% - This script processes ONE participant. Wrap steps 1-8 in a loop over
%   sub-01...sub-N, then grand-average result.pow_dist_avg across the saved
%   .mat files (align on dist_grid, which is identical across subjects by construction).
% - If left/right turns are separate corner_ids or come from a "direction" column
%   in corners.tsv/events.tsv, split pow_dist_by_corner accordingly for your
%   left-vs-right contrast instead of/in addition to collapsing across corners.
% - Baseline correction: doing it in the time-domain (step 4, cfg.baselinewindow)
%   before distance-warping is usually safer than trying to baseline in distance
%   space, since a fixed pre-corner *time* window is more comparable across
%   trials than a fixed pre-corner *distance* window walked at different speeds.
% - Motion channel names / BIDS entities (tracksys-*, columns in *_channels.tsv)
%   and EEG file extensions (.vhdr/.set/.edf) will need to match your actual dataset.
% - If EEG and motion were recorded on different systems, you must synchronize
%   them (e.g., shared trigger channel, common clock) before step 3 - the
%   fs_mot == fs_eeg assumption/assertion above is a placeholder for that.