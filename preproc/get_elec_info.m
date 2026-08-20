function [elecs] = get_elec_info()
eeg_elecs = {'AFz', 'Fz', 'Cz', 'C3', 'C4', 'Pz', 'PO3', 'PO4'}; 
allElecs  = ft_read_sens('standard_1020.elc'); % in fieldtrip templates
el_idx       = find(ismember(allElecs.label, eeg_elecs));
[elecs.chanpos, elecs.chantype, elecs.chanunit, elecs.elecpos, elecs.label, elecs.type, elecs.unit] = ...
    deal(allElecs.chanpos(el_idx,:), allElecs.chantype(el_idx), allElecs.chanunit(el_idx), ...
    allElecs.elecpos(el_idx,:), allElecs.label(el_idx), 'eeg1010', 'mm');

end
