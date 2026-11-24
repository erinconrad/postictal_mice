function s = processing_reason(message)
% PROCESSING_REASON  Plain-language reason a recording could not be
% processed, from the batch error message (postictal_results res.message).
% Used by make_results_report.m and write_cohort_spreadsheet.m.
%
%   s = processing_reason(res(i).message)
msg = lower(message);
if ~isempty(strfind(msg, 'after the end'))
    s = 'the recording ended before the (pseudo-)seizure offset';
elseif ~isempty(strfind(msg, 'raw stream'))
    s = 'the recording folder held two data streams';
elseif ~isempty(strfind(msg, 'flat signal'))
    s = 'the signal was flat (all samples equal) in part of the recording';
elseif ~isempty(strfind(msg, 'baseline'))
    s = 'there was too little artifact-free pre-heating baseline';
else
    s = 'the recording could not be processed';
end
end
