function [flag_failed,msg] = psom_run_job(file_job)
% Load some variables in a matlab file and run the corresponding job. 
% The function is generating empty files to flag the status of the 
% processing (running, failed or finished). 
%
% SYNTAX:
% [failed,MSG] = PSOM_RUN_JOB(FILE_JOB)
%
% _________________________________________________________________________
% COMMENTS:
%
% NOTE 1:
%
% This function is not meant to be used by itself. It is called by
% PSOM_PIPELINE_PROCESS and PSOM_RUN_PIPELINE
% 
% NOTE 2:
% When running a job, this function will create a global variable named
% "gb_psom_name_job". This can be accessed by the command executed by the
% job. This may be useful for example to build unique temporary file names.
% 
% Copyright (c) Pierre Bellec, Montreal Neurological Institute, 2008.
% Maintainer : pbellec@bic.mni.mcgill.ca
% See licensing information in the code.
% Keywords : pipeline

% Permission is hereby granted, free of charge, to any person obtaining a copy
% of this software and associated documentation files (the "Software"), to deal
% in the Software without restriction, including without limitation the rights
% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
% copies of the Software, and to permit persons to whom the Software is
% furnished to do so, subject to the following conditions:
%
% The above copyright notice and this permission notice shall be included in
% all copies or substantial portions of the Software.
%
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
% THE SOFTWARE.

global gb_psom_name_job
psom_gb_vars
psom_set_rand_seed();

try
    %% Generate file names
    [path_f,name_job,ext_f] = fileparts(file_job);

    if ~strcmp(ext_f,'.mat')
        error('The job file %s should be a .mat file !',file_job);
    end

    file_jobs     = [path_f filesep 'PIPE_jobs.mat'];
    file_running  = [path_f filesep name_job '.running'];
    file_failed   = [path_f filesep name_job '.failed'];
    file_finished = [path_f filesep name_job '.finished'];
    file_profile  = [path_f filesep name_job '.profile.mat'];
catch
    name_job = 'manual';
end
gb_psom_name_job = name_job;

try
    job = sub_load_job(file_jobs,name_job); % This is launched through the pipeline manager
    flag_psom = true;
catch
    if ischar(file_job)
        job = load(file_job);
    else
        job = file_job;
    end
    flag_psom = false;
end

if flag_psom
    if exist(file_running,'file')|exist(file_failed,'file')|exist(file_finished,'file')
        error('Already found a tag on that job. Sorry dude, I must quit ...');
    end
    
    %% Create a running tag for the job
    tmp = datestr(clock);
    save(file_running,'tmp')
end

%% Print general info about the job
start_time = clock;
msg = sprintf('Log of the (%s) job : %s\nStarted on %s\nUser: %s\nhost : %s\nsystem : %s',gb_psom_language,name_job,datestr(clock),gb_psom_user,gb_psom_localhost,gb_psom_OS);
stars = repmat('*',[1 30]);
fprintf('\n%s\n%s\n%s\n',stars,msg,stars);

%% Upload job info
gb_name_structure = 'job';
gb_list_fields    = {'files_in' , 'files_out' , 'files_clean' , 'command','opt' };
gb_list_defaults  = {{}         , {}          , {}            , NaN      , {}   };
psom_set_defaults
command, files_in, files_out, files_clean, opt

try
    %% The job starts now !
    msg = sprintf('The job starts now !');
    stars = repmat('*',[1 size(msg,2)]);
    fprintf('\n%s\n%s\n%s\n',stars,msg,stars);

    flag_failed = false;
   
    try
        eval(command)
        end_time = clock;
        elapsed_time = etime(end_time,start_time);
    catch
        end_time = clock;
        elapsed_time = etime(end_time,start_time);
        flag_failed = true;
        errmsg = lasterror;
        fprintf('\n\n%s\nSomething went bad ... the job has FAILED !\nThe last error message occured was :\n%s\n',stars,errmsg.message);
        if isfield(errmsg,'stack')
            for num_e = 1:length(errmsg.stack)
                fprintf('File %s at line %i\n',errmsg.stack(num_e).file,errmsg.stack(num_e).line);
            end
        end
    end
    
    %% Checking outputs
    msg = sprintf('Checking outputs');
    stars = repmat('*',[1 size(msg,2)]);
    fprintf('\n%s\n%s\n%s\n',stars,msg,stars);

    list_files = psom_files2cell(files_out);

    for num_f = 1:length(list_files)
        if ~psom_exist(list_files{num_f})&&~exist(list_files{num_f},'dir')
            fprintf('The output file or directory %s has not been generated!\n',list_files{num_f});
            flag_failed = true;
        else
            fprintf('The output file or directory %s was successfully generated!\n',list_files{num_f});
        end
    end                   

    %% Verbose an epilogue
    if flag_failed
        msg1 = sprintf('%s : The job has FAILED',datestr(clock));
    else
        msg1 = sprintf('%s : The job was successfully completed',datestr(clock));
    end
    msg2 = sprintf('Total time used to process the job : %1.2f sec.',elapsed_time);
    stars = repmat('*',[1 max(size(msg1,2),size(msg2,2))]);
    fprintf('\n%s\n%s\n%s\n%s\n',stars,msg1,msg2,stars);
    
    %% Create a tag file for output status
    if flag_psom   
        %% Check for double tag files
        if exist(file_failed)
            flag_failed = true;
            fprintf('Huho the job just finished but I found a FAILED tag. There must be something weird going on with the pipeline manager. Anyway, I will let the FAILED tag just in case ...');
        end     

        %% Create a profile
        save(file_profile,'start_time','end_time','elapsed_time');
        
        %% Finishing the job
        delete(file_running); 
        if flag_failed
            save(file_failed,'tmp')       
        else
            save(file_finished,'tmp')     
        end
    end
    
catch
    if flag_psom    
        delete(file_running);
        msg1 = sprintf('The job has FAILED');
        tmp = datestr(clock);
        save(file_failed,'tmp');
    end
    errmsg = lasterror;
    rethrow(errmsg)
end

%%%%%%%%%%%%%%%%%%
%% Subfunctions %%
%%%%%%%%%%%%%%%%%%

function job = sub_load_job(file_jobs,name_job)

load(file_jobs,name_job);
eval(['job = ' name_job ';']);
