% read in LabStreamingLayer data
% Mail Noah: 76 FPS bei den EEG Daten (13ms zwischen den einzelnen Datenpunkten mit einer Standardabweichung von 1 ms)
% AFz   19    N1P
% Fz    7     N2P
% Cz    Ref   N3P
% C3    16    N4P
% C4    10    N5P
% Pz    13    N6P
% PO3   28    N7P
% PO4   25    N8P
% F3    32    SRB2(REF, weiß)
% F4    21    BIAS(GND, Schwarz)

addpath('../../m-lib/fieldtrip/'); ft_defaults;
rawpath = ('../RAW/');
rawfile = 'eeg_data_long.csv';

Fs       = 250; % samples per second 
binsize  = 2; % 2 second bins for spectrum

tmp      = readmatrix([rawpath, rawfile]);
tmp(:,1) = tmp(:,1) - tmp(1,1); % set start to 0
n_epochs = floor(size(tmp, 1) / (Fs * binsize));

k   = shiftdim(tmp(:,2:9),1); % chan x time, for 8 channels
k   = k(:, 1: n_epochs*binsize*Fs);   % cut to full-length epochs
k2  = reshape(k, 8, Fs*binsize, n_epochs);
t   = 0:(1/Fs):(binsize-(1/Fs));
for cll = 1:size(k2,3)
rw{cll}   = k2(:,:,cll);
time{cll} = t;
end

raw.label = {'AFz'; 'Fz'; 'Cz'; 'C3'; 'C4'; 'Pz'; 'PO3'; 'PO4'};
raw.time  = time;
raw.trial = rw;

cfg = [];
cfg.output  = 'pow';
cfg.channel = 'all';
cfg.method  = 'mtmfft';
cfg.taper   = 'boxcar';
cfg.foi     = 2:1:20; % 1/cfg1.length  = 1;
base_freq1   = ft_freqanalysis(cfg, raw);

figure;
hold on;
plot(base_freq1.freq, base_freq1.powspctrm)
legend(raw.label);
xlabel('Frequency (Hz)');
ylabel('Power (uV^2)');


% Spektralanalyse für 2s - bins
