% HRB_MERGEPIPELINE - Merge one or more pipelines and reorder the fields.
% Fields are reordered if they end with a number, otherwise the order is
% not changed.
%
% Usage:
%     >> HRB_mergePipeline(pipeline)
%     >> HRB_mergePipeline(pipeline1,pipeline2,...)
%
% Inputs:
%    pipelineJSON = [struct] A struct with the pipeline. If all field names
%           end with a number it will be reordered.
%
%
% Authors: Alessandro Tonin, IRCCS San Camillo Hospital, 2024
% 
% See also: MERGESTRUCT

function pipeline = HRB_mergePipeline(pipelines)
    arguments (Repeating)
        pipelines struct
    end

    %% Merge pipelines
    if length(pipelines) == 1
        pipeline = pipelines{1};
    else
        pipeline = mergeStruct(pipelines{:},"addMissingFields",true);
    end

    %% Reorder fields
    % Extract numbers from fields
    expr = '\d+(_\d+)?$';
    fields_num = regexp(fieldnames(pipeline),expr,'match');
    all_fields_match = all(cellfun(@(x) length(x)==1,fields_num));
    if ~all_fields_match
        return
    end
    clean_num = cellfun(@(x) replace(x,'_','.'),fields_num);
    num = cellfun(@(x) str2double(x), clean_num);
    % get index
    [~,idx_ord] = sort(num);
    % change fields order
    pipeline = orderfields(pipeline,idx_ord);
end

