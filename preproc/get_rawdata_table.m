function [tbl, all_subs] = get_rawdata_table(rawPath)
tmp = dir(fullfile(rawPath, '**', 'participant_*.csv'));
tmp = tmp(~[tmp.isdir]);
tbl = struct2table(tmp);

tokens    = regexp(tbl.name, '_(.*?)\.', 'tokens'); % participant id
extracted = cellfun(@(c) c{1}{1}, tokens, 'UniformOutput', false);
two_digit_id = arrayfun(@(x) sprintf('sub-%02d', x), str2num(char(extracted)), ...
    'UniformOutput', false);
tokens = regexp(tbl.folder, '[^\\]+$', 'match');
extracted = cellfun(@(c) c{1}, tokens, 'UniformOutput', false);
tbl.condition = extracted;
tbl.two_digit_id = two_digit_id;
tbl = sortrows(tbl, 'two_digit_id');
condition_bidsname = cellfun(@(x) strrep(x, "results_", ""), tbl.condition);
condition_bidsname = cellfun(@(x) strrep(x, "_", ""), condition_bidsname);
tbl = addvars(tbl, condition_bidsname);
tbl = removevars(tbl, ["date", "bytes", "isdir", "datenum"]);
all_subs = unique(tbl.two_digit_id);

[counts, values] = groupcounts(tbl.two_digit_id);
T = table(values, counts); disp(T);

%[counts, values] = groupcounts(tbl.condition);
%T = table(values, counts); disp(T);

end
