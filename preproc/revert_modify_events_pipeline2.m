function [] = modify_events_pipeline2()
% from https://www.fieldtriptoolbox.org/example/other/bids_eeg/

%% paths and files
ftPath   = '../../../m-lib/fieldtrip/'; 
addpath(ftPath); ft_defaults;
bidsPath = '../../bids/';
rawPath  = '../../raw/pipeline2/final_data/';

%% get raw data file names and participants information
%[tbl, all_subs] = get_rawdata_table(rawPath);  % subfunction  

%% get bids event file names 
bids_tbl  = struct2table(dir(fullfile(bidsPath, '**', 'sub-*task-pedestrianNavigation_events.tsv')));
disp(fullfile(bids_tbl.folder, bids_tbl.name));
old_bids_tbl = struct2table(dir(fullfile(bidsPath, '**', 'sub-*task-pedestrianNavigation_events.tsv.old')));

new_evts_name = strcat(old_evts_name, '.old');
status = movefile(old_evts_name, new_evts_name); % rename old events file


%% new_ mini subject loop
for n = 1:numel(all_subs)
    sub  = all_subs(n);
    disp(sub);

    [idx, ~, ~] = get_session_files_in_order(tbl, sub);
    bids_idx    = find(contains(bids_tbl.name, sub));
    eegfilename = fullfile(tbl.folder(idx), tbl.name(idx));

     for k = 1:numel(eegfilename)
        % sample and session info
        opts = detectImportOptions(eegfilename{k});
        opts.SelectedVariableNames = {'timestamp'};
        protocol = readtable(eegfilename{k}, opts); 
        session_nr = repmat(k, height(protocol), 1);
        original_sample = [1:height(protocol)]';
        session_name = cellstr(repmat(tbl.condition_bidsname{idx(k)}, height(protocol), 1));
        tmp_protocol{k} = addvars(protocol, original_sample, session_nr, session_name, 'Before','timestamp');

        % BIDS event table
        opts_for_bids_table = detectImportOptions(eegfilename{k}); % just use one
        opts_for_bids_table.SelectedVariableNames = opts_for_bids_table.SelectedVariableNames([10:end]); % remove duplicate timestamp and eeg
        opts_for_bids_table = setvartype(opts_for_bids_table, opts_for_bids_table.VariableNames(12:end), 'char');
        bids_tmp = readtable(eegfilename{k}, opts_for_bids_table); 
        tmp_events{k} = bids_tmp;
      end

%     eeg      = horzcat(tmp_eeg{:}); clear tmp_eeg
     protocol = vertcat(tmp_protocol{:}); clear tmp_protocol
     protocol.timestamp = cellstr(datetime(datetime(protocol.timestamp, 'ConvertFrom', 'posixtime'),...
                            'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z'''));
     bids_events = [protocol, vertcat(tmp_events{:})]; clear tmp_events
     bids_add = bids_events(:, {'timestamp', 'label_opt_pos_abs', 'label_head_pos_abs'});   
     
     old_evts_name = char(fullfile(bids_tbl.folder(bids_idx), bids_tbl.name(bids_idx)));
     old_evts = ft_read_tsv(old_evts_name);
     old_evts = removevars(old_evts, 'label_opt_pos_abs');

     out_evts = join(old_evts, bids_add, 'Keys', 'timestamp');

     % rename old evts file
     new_evts_name = strcat(old_evts_name, '.old');
     status = movefile(old_evts_name, new_evts_name); % rename old events file
        if status
            disp('Renamed old events file');
        else
            warning('Rename failed');
        end
      ft_write_tsv(old_evts_name, out_evts); % save new events file under old file name  
end