function [] = convEEG2bids_CCC()
% from https://www.fieldtriptoolbox.org/example/other/bids_eeg/
%% paths and files
ftPath   = '../../../m-lib/fieldtrip/'; 
addpath(ftPath); ft_defaults;
bidsPath = '../../bids/';
rawPath  = '../../bids/sourcedata/';

%% per-subject information (modify these)
sub = 'CCC';
age = 24;
sex = 'f';
capsize = 60;

%% files
filepattern = {'Aurelia_eeg_one', 'Aurelia_eeg_two', 'Aurelia_eeg_three'};
bvisionname = [rawPath, sub, '_Aurelia_eeg.vhdr'];

tmp_eeg      = cell(size(filepattern));
tmp_protocol = cell(size(filepattern));

for fpart = 1:numel(filepattern)
    eegfilename = [rawPath, filepattern{fpart}, '.csv'];

    %% eeg data
    % data format description see https://docs.openbci.com/Software/OpenBCISoftware/GUIDocs/#exported-data; 
    % exclude 1st column with sample count and transpose to time x chan
    tmp_eeg{fpart}    = shiftdim(readmatrix(eegfilename, 'Range', 'C:J', NumHeaderLines = 1), 1); 

    %% read protocol; correct sample count and add run counter
    opts = detectImportOptions(eegfilename);
    opts.SelectedVariableNames = {'Var1', 'timestamp', 'x_pos', 'y_pos', 'ls_corner', 'ls_door'};
    tmp_protocol{fpart} = readtable(eegfilename, opts); 
    tmp_protocol{fpart}.Var1 = tmp_protocol{fpart}.Var1 + 1; % correct sample information
    run_nr = repmat(fpart, height(tmp_protocol{fpart}), 1);
    tmp_protocol{fpart} = addvars(tmp_protocol{fpart}, run_nr);
    tmp_protocol{fpart} = renamevars(tmp_protocol{fpart}, {'Var1', 'Var7'}, {'original_sample', 'run_nr'});
end

eeg      = horzcat(tmp_eeg{:}); clear tmp_eeg
protocol = vertcat(tmp_protocol{:}); clear tmp_protocol

%% convert time stamp, add continuous sample count
protocol.timestamp = cellstr(datetime(datetime(protocol.timestamp, 'ConvertFrom', 'posixtime'),...
                             'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
protocol = addvars(protocol, [1:height(protocol)]', 'Before', 'original_sample', 'NewVariableNames', 'sample');

%% find on- and offsets
target_doors = {'door_1', 'door_2', 'door_3', 'door_4', 'door_5'}; % leave out door_0, because there is no baseline available
on_off_doors = cellfun(@(x) (find(diff(ismember(protocol.ls_door, x))) + 1), target_doors, ...
                                'UniformOutput', false);
tmp_doors    = sort(reshape(cell2mat(on_off_doors), 2,[])');
res_doors    = [tmp_doors(:,1), tmp_doors(:,2) - tmp_doors(:,1)]; clear tmp_doors on_off_doors

target_corners    = {'corner_0', 'corner_1', 'corner_2', 'corner_3', };
on_off_corners    = cellfun(@(x) (find(diff(ismember(protocol.ls_corner, x))) + 1), target_corners, ...
    'UniformOutput', false);
tmp_corners    = sort(reshape(cell2mat(on_off_corners), 2,[])');
res_corners    = [tmp_corners(:,1), tmp_corners(:,2) - tmp_corners(:,1)]; clear tmp_doors on_off_doors

% also find landmark "null" (NULL event)
target_nulls = {'door_1', 'door_2';...
                'door_2', 'door_3'; ...
                'door_3', 'door_4'};
                %'door_4', 'door_5'};
get_half = @(lsdoor, in1, in2) max(find(ismember(lsdoor, in1))) + round((min(find(ismember(lsdoor, in2))) - max(find(ismember(lsdoor, in1))))/2);
indx = 0;
res_nulls = NaN(max(protocol.run_nr)*size(target_nulls, 1), 2);
add_prev_blockcount = [0, sum(protocol.run_nr==1), sum(ismember(protocol.run_nr, [1,2]))];
for run = 1:3
for nulls = 1:size(target_nulls, 1)
    indx = indx+1;
    res_nulls(indx, :) = [get_half(protocol.ls_door(protocol.run_nr==run), target_nulls{nulls, 1}, target_nulls{nulls, 2}) + add_prev_blockcount(run) ,1] ;
end
end
samples  = [res_doors; res_corners; res_nulls]; 
%samples     = all_samples(:, [1, 3]);
landmark = [cellstr(repmat('door', size(res_doors, 1), 1)); ...
            cellstr(repmat('corner', size(res_corners,1), 1)); ...
            cellstr(repmat('null', size(res_nulls, 1), 1))];

%% reduce protocol file and sort
proto = protocol(samples(:,1),:);
proto = addvars(proto, landmark, 'After', 'ls_door', 'NewVariableNames', 'landmark');
proto = sortrows(proto, 'sample');

plot(protocol.x_pos, protocol.y_pos);
ylabel('Distance relative to start (m)');
xlabel('Distance relative to start (m)');
%% electrodes
% AFz   19    N1P
% FCz    1    N2P
% C3    16    N3P 
% C4    10    N4P
% CPz    4    N5P
% Pz    13    N6P
% PO3   28    N7P
% PO4   25    N8P
% Cz    REF   SRB2(REF, weiß)
% F4    21    BIAS(GND, Schwarz)

%% to do: use equidistant layout???

eeg_elecs = {'AFz', 'Fz', 'Cz', 'C3', 'C4', 'Pz', 'PO3', 'PO4'}; 
allElecs  = ft_read_sens('standard_1020.elc'); % in fieldtrip templates
idx       = find(ismember(allElecs.label, eeg_elecs));
%elecs     = struct('chanpos', allElecs.chanpos(idx,:), 'chantype', allElecs.chantype(idx), ...
%               'chanunit', allElecs.chanunit(idx), 'elecpos', allElecs.elecpos(idx,:), ...
%               'label', allElecs.label(idx));
%elecs = []
[elecs.chanpos, elecs.chantype, elecs.chanunit, elecs.elecpos, elecs.label, elecs.type, elecs.unit] = ...
    deal(allElecs.chanpos(idx,:), allElecs.chantype(idx), allElecs.chanunit(idx), ...
    allElecs.elecpos(idx,:), allElecs.label(idx), 'eeg1010', 'mm');

clear eeg_elecs allElecs idx


%% header
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
% add further markers if necessary, e. g. for Hololens
%sample      = [1, 734]';
sample      = [1; proto.sample];
onset       = ((sample - 1) * (1/hdr.Fs));
%duration    = (zeros(numel(onset),1) + (1/hdr.Fs));
duration    = (([0; samples(:,2)]) * (1/hdr.Fs));
%markerValue = {''; 'S  1'};
markerValue = [{''}; cellstr(repmat('S  1', height(proto), 1))];
%markerType  = {'New Segment'; 'Stimulus'};
markerType = [{'New Segment'}; cellstr(repmat('Stimulus', height(proto), 1))];

%cfgtable    = table(sample, onset, duration, markerType, markerValue);
%cfgtable    = table(sample, onset, duration, markerType, markerValue, ...
%                    [protocol.timestamp(1); proto.timestamp], ...
%                    [NaN; proto.x_pos], [NaN; proto.y_pos], [NaN; proto.landmark], ...
%                    [NaN; proto.ls_corner], [NaN; proto.ls_door]);
cfgtable    = table(sample(2:end), onset(2:end), duration(2:end), markerType(2:end), markerValue(2:end), ...
                    proto.timestamp, proto.x_pos, proto.y_pos, proto.landmark, ...
                    proto.ls_corner, proto.ls_door);
cfgtable = renamevars(cfgtable, [cfgtable.Properties.VariableNames], ["sample", "onset", "duration","markerType", "markerValue", "timestamp", ...
    "x_pos", "y_pos", "landmark", "ls_corner", "ls_door"]);

event       = struct('type', markerType, 'sample', num2cell(sample), 'value', markerValue, ...
               'offset', [], 'duration', num2cell(duration), 'timestamp', []);
% muss cfgtable auch Eintrag für "new Segment" haben?
event(1).timestamp = proto.timestamp(1);

%% offset prüfen in evt struct

%protable = array2table(protocol.protocol, ...
%             'VariableNames', {'blocknum', 'trialnum', 'keyCode', 'rating', 'responseTime', ...
%             'movement', 'movType', 'plannedISI', 'actualISI', 'CueTime', 'TaskTime'});
%protable.movement = cellstr(categorical(protable.movement, 1:3, {'mouth', 'shoulder', 'forward'}));
%protable.movType  = cellstr(categorical(protable.movType, 21:22, {'real', 'imagined'}));
%alltable = [cfgtable, protable]; % added information from stimulus protocol file
%alltable.type = char(alltable.type);
%alltable     = cfgtable;

%% convert to brainvision format
ft_write_data(bvisionname, eeg, 'dataformat', 'brainvision_eeg', 'header', hdr, 'event', event);

%% convert to BIDS format
cfg = [];
cfg.method    = 'copy';
cfg.suffix    = 'eeg';
cfg.dataset   = bvisionname;
cfg.bidsroot  = bidsPath;
cfg.sub       = sub;
cfg.scans.acq_time = char(event(1).timestamp);

cfg.participants.age = age;
cfg.participants.sex = sex;

cfg.InstitutionName             = 'University of Regensburg';
cfg.InstitutionalDepartmentName = 'Institute for Psychology';
cfg.InstitutionAddress          = 'Universitaetsstrasse 31, 93053 Regensburg, Germany';
cfg.Manufacturer                = 'OpenBCI, New York, USA';
cfg.ManufacturersModelName      = 'Cyton';
cfg.dataset_description.Name    = 'Action Decoding during indoor navigation';
cfg.dataset_description.Authors = {'Gregor Volberg', 'Angelika Lingnau', 'Bernd Ludwig'};

cfg.TaskName        = 'actionDecoding';
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
cfg.eeg.HeadCircumference  = capsize; 

cfg.electrodes                      = elecs;
cfg.electrodes.type                 = 'ring';
cfg.electrodes.material             = 'Ag/AgCl'; 
cfg.coordsystem.EEGCoordinateSystem = 'CapTrak'; % RAS orientation
cfg.coordsystem.EEGCoordinateUnits  = 'mm';

%% these do not work

cfg.events = cfgtable;

data2bids(cfg);

end