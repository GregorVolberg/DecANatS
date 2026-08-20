function [] = convEEG2bids_neurips()
% from https://www.fieldtriptoolbox.org/example/other/bids_eeg/

%% paths and files
ftPath   = '../../../m-lib/fieldtrip/'; 
addpath(ftPath); ft_defaults;
bidsPath = '../../bids/';
rawPath  = '../../bids/sourcedata/';
bidsTask = '_task-pedestrianNavigation';

%% get raw data files, participants and electrodes information
[tbl, all_subs] = get_rawdata_table(rawPath);  % subfunction  
elecs = get_elec_info(); % subfunction

%% per-subject information
age     = repmat({'n/a'}, numel(all_subs), 1);
sex     = {'m', 'm', 'm', 'm', 'f', 'm', 'm', 'm', 'f', 'm'};
capsize = 56 + ismember(sex, 'm')*2; % all f 56, all m 58

%% set general import options

%% new_ mini subject loop
for n = 1:3%numel(all_subs)
    sub  = all_subs(n);
    [idx, ~, ~] = get_session_files_in_order(tbl, sub);
    eegfilename = fullfile(tbl.folder(idx), tbl.name(idx));
    bvisionname = fullfile(rawPath, [char(sub), '.vhdr']);

     for k = 1:numel(eegfilename)
        % sample and session info
        opts = detectImportOptions(eegfilename{k});
        opts.SelectedVariableNames = {'timestamp'};
        protocol = readtable(eegfilename{k}, opts); 
        session_nr = repmat(k, height(protocol), 1);
        original_sample = [1:height(protocol)]';
        session_name = cellstr(repmat(tbl.condition_bidsname{idx(k)}, height(protocol), 1));
        tmp_protocol{k} = addvars(protocol, original_sample, session_nr, session_name, 'Before','timestamp');

       % eeg
        opts.DataLines = [2 Inf];           % skip header line
        opts.SelectedVariableNames = opts.VariableNames(2:9);  % only columns 2 to 9, i. e. EEG channels 1:8
        tmp_eeg{k} = shiftdim(readmatrix(eegfilename{k}, opts), 1);

       % get BIDS event table
        opts_for_bids_table = detectImportOptions(eegfilename{k}); % just use one
        opts_for_bids_table.SelectedVariableNames = opts_for_bids_table.SelectedVariableNames([10:end]); % remove duplicate timestamp and eeg
        opts_for_bids_table = setvartype(opts_for_bids_table, opts_for_bids_table.VariableNames(12:end), 'char');
        bids_tmp = readtable(eegfilename{k}, opts_for_bids_table); 
        tmp_events{k} = bids_tmp;
        % if ~iscell(tmp_events{k}.label_sak) % corrects numeric data to cellstr
        %     tmp_events{k}.label_sak = cellstr(num2str(tmp_events{k}.label_sak));
        % end
        % if ~iscell(tmp_events{k}.head_yaw_offset_deg) % corrects numeric data to cellstr
        %     tmp_events{k}.head_yaw_offset_deg = cellstr(num2str(tmp_events{k}.head_yaw_offset_deg));
        % end
        % if ~iscell(tmp_events{k}.head_yaw_deg) % corrects numeric data to cellstr
        %     tmp_events{k}.head_yaw_deg = cellstr(num2str(tmp_events{k}.head_yaw_deg));
        % end
        % if ~iscell(tmp_events{k}.head_yaw_delta_deg) % corrects numeric data to cellstr
        %     tmp_events{k}.head_yaw_delta_deg = cellstr(num2str(tmp_events{k}.head_yaw_delta_deg));
        % end
        

      end

     eeg      = horzcat(tmp_eeg{:}); clear tmp_eeg
     protocol = vertcat(tmp_protocol{:}); clear tmp_protocol
     protocol.timestamp = cellstr(datetime(datetime(protocol.timestamp, 'ConvertFrom', 'posixtime'),...
                            'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z'''));
     bids_events = [protocol, vertcat(tmp_events{:})]; clear tmp_events

    % BV export information: eeg data, header structure, event structure
    hdr = [];
    hdr.Fs          = 250; % sampling frequency
    hdr.nChans      = 8; % number of channels
    hdr.nSamples    = size(eeg,2); % number of samples per trial
    hdr.nSamplesPre = 0; % number of pre-trigger samples in each trial
    hdr.nTrials     = 1; % number of trials
    hdr.label       = elecs.label; % Nx1 cell-array with the label of each channel
    hdr.chantype    = elecs.chantype; % Nx1 cell-array with the channel type, see FT_CHANTYPE
    hdr.chanunit    = elecs.chanunit; % Nx1 cell-array with the physical units, see FT_CHANUNIT


    %% events and onsets
    sample      = [1:height(protocol)]';
    onset       = ((sample - 1) * (1/hdr.Fs));
    duration    = repmat(1/250, height(protocol), 1);%(([0; samples(:,2)]) * (1/hdr.Fs));
    markerValue = cellstr(repmat('S  1', height(protocol), 1)); %[{''}; cellstr(repmat('S  1', height(proto), 1))];
    markerType  = cellstr(repmat('Stimulus', height(protocol), 1)); %[{'New Segment'}; cellstr(repmat('Stimulus', height(proto), 1))];
    event       = struct('type', markerType, 'sample', num2cell(sample), 'value', markerValue, ...
                   'offset', [], 'duration', num2cell(duration), 'timestamp', []);
    bids_events = addvars(bids_events,  sample, onset, duration, 'Before', 'original_sample');

    % write BV
    ft_write_data(bvisionname, eeg, 'dataformat', 'brainvision_eeg', 'header', hdr, 'event', event);

    % write BIDS data
    cfg = [];
    cfg.method    = 'copy';
    cfg.suffix    = 'eeg';
    cfg.dataset   = bvisionname;
    cfg.bidsroot  = bidsPath;
    cfg.sub       = char(strrep(sub, 'sub-', ''));
    cfg.scans.acq_time = protocol.timestamp(1);

    cfg.participants.age = age(n);
    cfg.participants.sex = sex(n);
        
    cfg.InstitutionName             = 'University of Regensburg';
    cfg.InstitutionalDepartmentName = 'Institute for Psychology';
    cfg.InstitutionAddress          = 'Universitaetsstrasse 31, 93053 Regensburg, Germany';
    cfg.Manufacturer                = 'OpenBCI, New York, USA';
    cfg.ManufacturersModelName      = 'Cyton';
    cfg.dataset_description.Name    = 'Action Decoding during indoor navigation';
    cfg.dataset_description.Authors = {'Gregor Volberg', 'Angelika Lingnau', 'Bernd Ludwig', 'Noah Meissner', ...
            'Ann-Christin Täubert', 'Jonas Bachmeier'};
        
    cfg.TaskName        = 'pedestrianNavigation';
    cfg.TaskDescription = 'EEG was recorded on freely moving participants in an indoor navigation task.';
        
    cfg.eeg.PowerLineFrequency = 50;   
    cfg.eeg.EEGReference       = 'Cz';
    cfg.eeg.EEGGround          = 'F4'; 
    cfg.eeg.CapManufacturer    = 'EasyCap'; 
    cfg.eeg.CapManufacturersModelName = 'M10-X'; %
    cfg.eeg.EEGChannelCount    = 8;
    cfg.eeg.EOGChannelCount    = 0; 
    cfg.eeg.RecordingType      = 'continuous';
    cfg.eeg.EEGPlacementScheme = 'equidistant';
    cfg.eeg.SoftwareFilters    = 'n/a';
    cfg.eeg.HeadCircumference  = capsize(n); 

    cfg.events = bids_events;
         
    data2bids(cfg);
 end
end

% 
% 
% 
% 
% 
% 
% % % concat
% % % https://www.fieldtriptoolbox.org/faq/preproc/datahandling/append_files/
% % for k = 1:numel(idx)
% % hdr{k} = ft_read_header(eegfilebids(k));
% % dat{k} = ft_read_data(eegfilebids(k));
% % evt{k} = ft_read_event(eegfilebids(k));
% % end
% 
% 
%         eegfilename = char(fullfile(tbl.folder(idx(k)), tbl.name(idx(k))));
%         bvisionname = fullfile(bidsPath, char(tbl.two_digit_id(idx(k))), ses, ...
%             [tbl.two_digit_id{idx(k)}, bidsTask, '_', ses, '_eeg.vhdr']);
% 
% 
% 
% 
% 
% 
% %% subject loop
% for n = 1:numel(all_subs)
%     sub  = all_subs(n);
%     [idx, acq_time, acq_order] = get_session_files_in_order(tbl, sub);
% 
%     for k = 1:numel(idx)
%         ses = sprintf('ses-%s', tbl.condition_bidsname(idx(k)));
%         eegfilename = char(fullfile(tbl.folder(idx(k)), tbl.name(idx(k))));
%         bvisionname = fullfile(bidsPath, char(tbl.two_digit_id(idx(k))), ses, ...
%             [tbl.two_digit_id{idx(k)}, bidsTask, '_', ses, '_eeg.vhdr']);
% 
%         % sample and session info
%         opts = detectImportOptions(eegfilename);
%         opts.SelectedVariableNames = {'timestamp'};
%         protocol = readtable(eegfilename, opts); 
%         protocol.timestamp = cellstr(datetime(datetime(protocol.timestamp, 'ConvertFrom', 'posixtime'),...
%                              'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z'''));
%         session_nr = repmat(k, height(protocol), 1);
%         original_sample = [1:height(protocol)]';
%         session_name = cellstr(repmat(tbl.condition_bidsname{idx(k)}, height(protocol), 1));
%         protocol = addvars(protocol, session_nr, original_sample, session_name, 'Before','timestamp');
% 
%         % eeg
%         opts.DataLines = [2 Inf];           % skip header line
%         opts.SelectedVariableNames = opts.VariableNames(2:9);  % only columns 2 to 9, i. e. EEG channels 1:8
%         eeg = shiftdim(readmatrix(eegfilename, opts), 1);
% 
%         % construct BV header
%         hdr = [];
%         hdr.Fs          = 250; % sampling frequency
%         hdr.nChans      = 8; % number of channels
%         hdr.nSamples    = size(eeg,2); % number of samples per trial
%         hdr.nSamplesPre = 0; % number of pre-trigger samples in each trial
%         hdr.nTrials     = 1; % number of trials
%         hdr.label       = elecs.label; % Nx1 cell-array with the label of each channel
%         hdr.chantype    = elecs.chantype; % Nx1 cell-array with the channel type, see FT_CHANTYPE
%         hdr.chanunit    = elecs.chanunit; % Nx1 cell-array with the physical units, see FT_CHANUNIT
% 
%         % events and onsets
%         sample      = [1; protocol.original_sample];
%         onset       = ((sample - 1) * (1/hdr.Fs));
%         duration = ones(height(sample),1) * (1/hdr.Fs);
%         markerValue = [{''}; cellstr(repmat('S  1', height(protocol), 1))];
%         markerType = [{'New Segment'}; cellstr(repmat('Stimulus', height(protocol), 1))];
% 
%         cfgtable = table(sample(2:end), onset(2:end), duration(2:end), markerType(2:end), markerValue(2:end));
%         cfgtable = renamevars(cfgtable, [cfgtable.Properties.VariableNames], ["sample", "onset", "duration","markerType", "markerValue"]);
%         cfgtable = [cfgtable, protocol];
%         event       = struct('type', markerType, 'sample', num2cell(sample), 'value', markerValue, ...
%                        'offset', [], 'duration', num2cell(duration), 'timestamp', []);
% 
%         % get BIDS event table
%         opts_for_bids_table = detectImportOptions(eegfilename); % just use one
%         opts_for_bids_table.SelectedVariableNames = opts_for_bids_table.SelectedVariableNames(10:end); % remove duplicate timestamp and eeg
%         bids_tmp = readtable(eegfilename, opts_for_bids_table); 
%         bids_events = [cfgtable, bids_tmp];    
% 
%         % write BVision data
%         ft_write_data(bvisionname, eeg, 'dataformat', 'brainvision_eeg', 'header', hdr, 'event', event);
% 
%         % write BIDS data
%         cfg = [];
%         cfg.method    = 'copy';
%         cfg.suffix    = 'eeg';
%         cfg.dataset   = bvisionname;
%         cfg.bidsroot  = bidsPath;
%         cfg.sub       = char(strrep(sub, 'sub-', ''));
%         cfg.ses       = char(strrep(ses, 'ses-', ''));
%         cfg.scans.acq_time = acq_time(acq_order(k)); %cfgtable.timestamp(1);
% 
%         cfg.participants.age = age(n);
%         cfg.participants.sex = sex(n);
% 
%         cfg.InstitutionName             = 'University of Regensburg';
%         cfg.InstitutionalDepartmentName = 'Institute for Psychology';
%         cfg.InstitutionAddress          = 'Universitaetsstrasse 31, 93053 Regensburg, Germany';
%         cfg.Manufacturer                = 'OpenBCI, New York, USA';
%         cfg.ManufacturersModelName      = 'Cyton';
%         cfg.dataset_description.Name    = 'Action Decoding during indoor navigation';
%         cfg.dataset_description.Authors = {'Gregor Volberg', 'Angelika Lingnau', 'Bernd Ludwig', 'Noah Meissner', ...
%             'Ann-Christin Täubert', 'Jonas Bachmeier'};
% 
%         cfg.TaskName        = 'pedestrianNavigation';
%         cfg.TaskDescription = 'EEG was recorded on freely moving participants in an indoor navigation task.';
% 
%         cfg.eeg.PowerLineFrequency = 50;   
%         cfg.eeg.EEGReference       = 'Cz';
%         cfg.eeg.EEGGround          = 'F4'; 
%         cfg.eeg.CapManufacturer    = 'EasyCap'; 
%         cfg.eeg.CapManufacturersModelName = 'M10-X'; %
%         cfg.eeg.EEGChannelCount    = 8;
%         cfg.eeg.EOGChannelCount    = 0; 
%         cfg.eeg.RecordingType      = 'continuous';
%         cfg.eeg.EEGPlacementScheme = 'equidistant';
%         cfg.eeg.SoftwareFilters    = 'n/a';
%         cfg.eeg.HeadCircumference  = capsize(n); 
% 
%         cfg.events = bids_events;
% 
%         data2bids(cfg);
%     end
% end
% end
