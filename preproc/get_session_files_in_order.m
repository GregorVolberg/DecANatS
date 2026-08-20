function [idx, t_yyyy, t_idx] = get_session_files_in_order(tbl, sub)
 
    idx = find(ismember(tbl.two_digit_id, sub));
    flist = arrayfun(@(x) fullfile(tbl.folder(x), tbl.name(x)), idx);
    t_unix = nan(numel(flist),1);
    % find out recording time of sessions, then sort accordingly
    for srt = 1:numel(flist)
        opts = detectImportOptions(flist{srt});
        opts.SelectedVariableNames = {'timestamp'};
        tmp = readtable(flist{srt}, opts); 
        tstamp = datetime(datetime(tmp.timestamp, 'ConvertFrom', 'posixtime'),...
                                 'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z''');
        t_yyyy(srt) = tstamp(1);
        nrows(srt) = height(tmp);
    end
    [~, t_idx] = sort(t_yyyy);
    idx   = idx(t_idx);
    
    %nrows = nrows(t_idx);
end
