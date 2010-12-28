function file_pipeline = psom_pipeline_init(pipeline,opt)
% Prepare the log folders of a pipeline before execution by PSOM.
%
% When the pipeline is executed for the first time, that means 
% initialize the dependency graph, store individual job description 
% in a matlab file, and initialize status and logs. 
%
% If the pipeline is restarted after some failures or update of some of the 
% jobs' parameters, the job status and logs are "refreshed" to make 
% everything ready before restart. See the notes in the COMMENTS section
% below for details.
%
% SYNTAX:
% FILE_PIPELINE = PSOM_PIPELINE_INIT(PIPELINE,OPT)
%
% _________________________________________________________________________
% INPUTS:
%
% * PIPELINE
%       (structure) a matlab structure which defines a pipeline.
%       Each field name <JOB_NAME> will be used to name the corresponding
%       job. The fields <JOB_NAME> are themselves structure, with
%       the following fields :
%
%       COMMAND
%           (string) the name of the command applied for this job.
%           This command can use the variables FILES_IN, FILES_OUT and OPT
%           associated with the job (see below).
%           Examples :
%               'niak_brick_something(files_in,files_out,opt);'
%               'my_function(opt)'
%
%       FILES_IN
%           (string, cell of strings, structure whose terminal nodes are
%           string or cell of strings)
%           The argument FILES_IN of the BRICK. Note that for properly
%           handling dependencies, this field needs to contain the exact
%           name of the file (full path, no wildcards, no '' for default
%           values).
%
%       FILES_OUT
%           (string, cell of strings, structure whose terminal nodes are
%           string or cell of strings) the argument FILES_OUT of
%           the BRICK. Note that for properly handling dependencies, this
%           field needs to contain the exact name of the file
%           (full path, no wildcards, no '' for default values).
%
%       OPT
%           (any matlab variable) options of the job. This field has no
%           impact on dependencies. OPT can for example be a structure,
%           where each field will be used as an argument of the command.
%
% * OPT
%       (structure) with the following fields :
%
%       PATH_LOGS
%           (string) The folder where the .mat files will be stored. That
%           folder needs to be empty, and left untouched during the whole
%           pipeline processing. Renaming or deleting files from the
%           PATH_LOGS may result in unrecoverable crash of the pipeline.
%
%       PATH_SEARCH
%           (string, default current matlab search path) the matlab search
%           path that will be used by the jobs. if PATH_SEARCH is empty,
%           the default is used. If PATH_SEARCH equals 'gb_psom_omitted',
%           then PSOM will not attempt to set the search path, i.e. the
%           search path for every job will be the current search path in
%           'session' mode, and the default Octave/Matlab search path in
%           the other modes.
%
%       COMMAND_MATLAB
%           (string, default GB_PSOM_COMMAND_MATLAB or
%           GB_PSOM_COMMAND_OCTAVE depending on the current environment)
%           how to invoke Matlab (or Octave).
%           You may want to update that to add the full path of the command.
%           The defaut for this field can be set using the variable
%           GB_PSOM_COMMAND_MATLAB/OCTAVE in the file PSOM_GB_VARS.
%
%       RESTART
%           (cell of strings, default {}) any job whose name contains one 
%           of the strings in RESTART will be restarted, along with all of 
%           its children, and some of his parents whenever needed. See the
%           note 3 for more details.
%
%       FLAG_UPDATE
%           (boolean, default true) If FLAG_UPDATE is true, a comparison
%           between previous pipelines and the current pipeline will be
%           performed to restart updated jobs. 
%       
%       FLAG_PAUSE
%           (boolean, default false) If FLAG_PAUSE is true, the pipeline
%           initialization may pause in some situations, i.e. before
%           writting an update of a pipeline (and incidentally flush old
%           outputs) and before starting a pipeline if some necessary input 
%           files are missing. This lets the user an opportunity to cancel
%           the pipeline execution before anything is written on the disk.
%
%       FLAG_CLEAN
%           (boolean, default true) if FLAG_CLEAN is true, before a job is
%           restarted all files named as the outputs will be deleted. This
%           is to avoid any confusion as of when a particular output has
%           been created, in case overwritting would not be successfull.
%           This behavior may not be desirable when a particular job is
%           actually able to recover from where it was interrupted.
%
%       FLAG_VERBOSE
%           (boolean, default true) if the flag is true, then the function 
%           prints some infos during the processing.
%
% _________________________________________________________________________
% OUTPUTS:
%
% FILE_PIPELINE
%       (string) the file name of the .MAT file recapitulating all the
%       infos on the pipeline
%
% _________________________________________________________________________
% SEE ALSO:
% PSOM_PIPELINE_PROCESS, PSOM_PIPELINE_VISU, PSOM_DEMO_PIPELINE,
% PSOM_RUN_PIPELINE
%
% _________________________________________________________________________
% COMMENTS:
%
% The following notes describe the stages performed by PSOM_PIPELINE_INIT 
% in a chronological order.
%
% * STAGE 1:
%
%   The dependency graph of the pipeline is defined as follows: job A 
%   depends on job B if at least one of the two following conditions is 
%   satisfied : 
%       1. the input files of job A belongs to the list of output files of 
%       job B. 
%       2. the job B will clean (i.e. delete) some files that job A uses as 
%       inputs.
%   See PSOM_BUILD_DEPENDENCIES and PSOM_VISU_DEPENDENCIES for details.
%
%   Some viability checks are performed on the pipeline :
%
%       1. Check that the dependency graph of the pipeline is a directed 
%       acyclic graph, i.e. if job A depends on job B, job B cannot depend 
%       (even indirectly) on job A. 
%
%       2. Check that an output file is not created twice. Overwritting on 
%       files is regarded as a bug in a pipeline (forgetting to edit a 
%       copy-paste is a common mistake that leads to overwritting).
%   
% * STAGE 2:
%
%   Load old descriptions of the pipeline, if any can be found in the logs
%   folder. This includes the description of the jobs, logs and status.
%
%   The following strategy is implemented to initialize the logs and job
%   status based on old values :
%
%       1. If a job is marked as 'none' but a log file and a 'finished' tag 
%       files can be found, then the job is marked as 'finished' and the 
%       log is saved in the log structure. (That behavior is usefull when 
%       the pipeline manager has crashed but some jobs completed after the 
%       crash in batch or qsub modes, thus generating left-over tags). 
%
%       2. Unless the job already has a 'finished' status and is not marked 
%       as 'restart', its status is set to 'none' and the log file is 
%       re-initialized as blank.
%
%       3. If a job was marked as 'finished' and is not marked as 
%       'restart', its status is left as 'finished' and the log file is 
%       also left "as is". Note that even if the outputs do not exist 
%       (because they have been deleted since the pipeline was last 
%       executed) the job will not be restarted. 
%
% * STAGE 3:
%
%   Some 'restart' flags are generated for each job: 
%
%       1. If a job was already processed during a previous execution of the 
%       pipeline, but anything changed in the job description (the 
%       command line, the options or the names of inputs/outputs), then the 
%       job will be marked as 'restart'. This operation is done by 
%       comparing the content of the variable <JOB_NAME> in PIPE_jobs.mat 
%       with the field PIPELINE.<JOB_NAME>. This feature can be turned
%       on/off using OPT.FLAG_UPDATE.
%
%       2. All jobs whose name contains at least one of the strings listed 
%       in OPT.RESTART will be marked as 'restart'. 
%
%       3. All jobs that depend even indirectly on a job marked as 
%       'restart' (in the sense of the dependency graph) are themselves 
%       marked as 'restart'.
%
%       4. If a job is marked as 'restart' and is using input files that do
%       not exist but can be generated by another job, this other job is
%       also marked as 'restart'. This behavior is implemented recursively.
%
%       5. Steps 3 and 4 are iterated until no additional jobs were set to
%       restart.
%
% * STAGE 4: 
%   
%   The current description of the pipeline is saved in the logs folder.
%
%   The directory PATH_LOGS is created if necessary. A description of the
%   pipeline, its dependencies and the matlab environment are saved in the 
%   following file : 
%
%   <PATH_LOGS>/PIPE.mat
%       A .MAT file with the following variables:
%
%       OPT
%           The options used to initialize the pipeline
%
%       HISTORY
%           A string recapituling when and who created the pipeline, (and
%           on which machine).
%
%       DEPS, LIST_JOBS, FILES_IN, FILES_OUT, GRAPH_DEPS
%           See PSOM_BUILD_DEPENDENCIES for more info.
%
%       PATH_WORK
%           The matlab/octave search path
%
%   Some individual descriptions of the jobs are saved in the following 
%   file : 
%
%   <PATH_LOGS>/PIPE_jobs.mat
%       A .MAT file with the following variables:
%
%       <JOB_NAME>
%           One variable per job. It is identical to PIPELINE.<JOB_NAME>.
%
%   The logs and status of all the jobs are initialized and saved in the
%   two following files : 
%
%   <PATH_LOGS>/PIPE_status.mat
%       A .mat file with the following variable : 
%
%       JOB_STATUS
%           A structure. Each field corresponds to one job name and is a
%           string describing the current status of the job (upon
%           initialization, it is 'none', meaning that nothing has been
%           done with the job yet). See PSOM_JOB_STATUS and the following
%           notes for other status.
%
%   <PATH_LOGS>/PIPE_logs.mat
%       A .mat file with the following variable : 
%       
%       <JOB_NAME>
%           (string) the log of the job.
%
% * STAGE 5:
%
%   The pipeline is preparing to the execution phase :
%
%       1. If a job has a 'none' status, the system checks if all the 
%       inputs exist, apart from the files that will be generated by other 
%       jobs. If some files are missing, this is specified in the log and 
%       the job is marked as 'failed'. Note that if any job has failed 
%       this way, the pipeline initialization will pause to let the user 
%       the time to cancel the execution of the pipeline.
%
%       2. The folders for outputs are created. 
%
%       3. Existing files with names similar to the outputs are deleted. 
%
%   	4. Existing tag/log/exit/qsub files in the logs folder are deleted, 
%       as well as the 'tmp' subfolder, if it exists.
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

%%%%%%%%%%%%%%%%%%%%%
%% Checking inputs %%
%%%%%%%%%%%%%%%%%%%%%

psom_gb_vars

%% Syntax
if ~exist('pipeline','var')||~exist('opt','var')
    error('syntax: FILE_PIPELINE = PSOM_PIPELINE_INIT(PIPELINE,OPT).\n Type ''help psom_pipeline_init'' for more info.')
end

%% Options
gb_name_structure = 'opt';
gb_list_fields    = {'flag_clean' , 'flag_pause' , 'flag_update' , 'path_search'       , 'restart' , 'path_logs' , 'command_matlab' , 'flag_verbose' };
gb_list_defaults  = {true         , false        , true          , gb_psom_path_search , {}        , NaN         , ''               , true           };
psom_set_defaults
name_pipeline = 'PIPE';

if isempty(path_search)
    path_search = path;
    opt.path_search = path_search;
end

if isempty(opt.command_matlab)
    if strcmp(gb_psom_language,'matlab')
        opt.command_matlab = gb_psom_command_matlab;
    else
        opt.command_matlab = gb_psom_command_octave;
    end
end

%% Misc variables
hat_qsub_o = sprintf('\n\n*****************\nOUTPUT QSUB\n*****************\n');
hat_qsub_e = sprintf('\n\n*****************\nERROR QSUB\n*****************\n');

%% Print a small banner for the initialization
if flag_verbose
    msg_line1 = sprintf('The pipeline description is now being prepared for execution.');
    msg_line2 = sprintf('The following folder will be used to store logs and status :');
    msg_line3 = sprintf('%s',path_logs);
    size_msg = max([size(msg_line1,2),size(msg_line2,2),size(msg_line3,2)]);
    msg = sprintf('%s\n%s\n%s',msg_line1,msg_line2,msg_line3);
    stars = repmat('*',[1 size_msg]);
    fprintf('\n%s\n%s\n%s\n',stars,msg,stars);
end

%% Generate file names 
file_pipeline = cat(2,path_logs,filesep,name_pipeline,'.mat');
file_jobs = cat(2,path_logs,filesep,name_pipeline,'_jobs.mat');
file_jobs_backup = cat(2,path_logs,filesep,name_pipeline,'_jobs_backup.mat');
file_logs = cat(2,path_logs,filesep,name_pipeline,'_logs.mat');
file_logs_backup = cat(2,path_logs,filesep,name_pipeline,'_logs_backup.mat');
file_status = cat(2,path_logs,filesep,name_pipeline,'_status.mat');
file_status_backup = cat(2,path_logs,filesep,name_pipeline,'_status_backup.mat');
list_jobs = fieldnames(pipeline);
nb_jobs = length(list_jobs);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Stage 1: Build the dependency graph and check the viability of the pipeline %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if flag_verbose
    fprintf('Examining the dependencies of the pipeline ...\n');
end

%% Check that all jobs have a "command" field
if flag_verbose
    fprintf('    Checking that all jobs are associated with a command ...\n');
end

for num_j = 1:nb_jobs
    if ~isfield(pipeline.(list_jobs{num_j}),'command')
        error('The job %s has no ''command'' field. Sorry dude, I cannot process that pipeline.\n',list_jobs{num_j});
    end
end

%% Generate dependencies

if flag_verbose
    fprintf('    Generating dependencies ...\n');
end

[graph_deps,list_jobs,files_in,files_out,files_clean,deps] = psom_build_dependencies(pipeline,opt.flag_verbose);

%% Check if some outputs were not generated twice
if flag_verbose
    fprintf('    Checking if some outputs were not generated twice ...\n');
end

[flag_ok,list_files_failed,list_jobs_failed] = psom_is_files_out_ok(files_out);

if ~flag_ok    
    for num_f = 1:length(list_files_failed)
        if num_f == 1
            str_files = list_files_failed{num_f};
        else
            str_files = [str_files ' ; '  list_files_failed{num_f}];
        end
    end
    
    for num_j = 1:length(list_jobs_failed)
        if num_j == 1
            str_jobs = list_jobs_failed{num_j};
        else
            str_jobs = [str_jobs ' ; ' list_jobs_failed{num_j}];
        end
    end

    error('The following output files are generated multiple times : %s.\nThe following jobs are responsible for that : %s',str_files,str_jobs);
end

%% Check for cycles

if flag_verbose
    fprintf('    Checking if the graph of dependencies is acyclic ...\n');
end

[flag_dag,list_vert_cycle] = psom_is_dag(graph_deps);

if ~flag_dag
    
    for num_f = 1:length(list_vert_cycle)
        if num_f == 1
            str_files = list_jobs{list_vert_cycle(num_f)};
        else
            str_files = [str_files ' ; '  list_jobs{list_vert_cycle(num_f)}];
        end
    end
    error('There are cycles in the dependency graph of the pipeline. The following jobs are involved in at least one cycle : %s',str_files);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Stage 2: Load previous pipeline description, logs and status %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Test for the existence of an old pipeline 

flag_old_pipeline = exist(file_jobs,'file');

if flag_old_pipeline

    if flag_verbose
        fprintf('\nLoading previous pipeline ...\n');
    end

    %% Old jobs
    if flag_verbose
        fprintf('    Loading old jobs ...\n');
    end
    try
        pipeline_old = load(file_jobs);
    catch
        warning('There was something wrong when loading the old job description file %s, I''ll try loading the backup instead',file_jobs)
        pipeline_old = load(file_jobs_backup);
        copyfile(file_jobs_backup,file_jobs,'f');
    end
    
    %% Old status
    if flag_verbose
        fprintf('    Loading old status ...\n');
    end
    if exist(file_status,'file')
        try
            all_status_old = load(file_status);
        catch
            warning('There was something wrong when loading the old status file %s, I''ll try loading the backup instead',file_status)
            all_status_old = load(file_status_backup);
            copyfile(file_status_backup,file_status,'f');
        end
    else
        for num_j = 1:nb_jobs
            name_job = list_jobs{num_j};
            all_status_old.(name_job) = 'none';
        end
    end
    
    %% Old logs
    if flag_verbose
        fprintf('    Loading old logs ...\n');
    end
    if exist(file_logs,'file')
        try
            all_logs_old = load(file_logs);
        catch
            warning('There was something wrong when loading the old logs file %s, I''ll try loading the backup instead',file_logs)
            all_logs_old = load(file_logs_backup);
            copyfile(file_logs_backup,file_logs,'f');
        end
    else
        all_logs_old = struct([]);
    end
    
else

    pipeline_old = struct([]);
    all_status_old = struct([]);
    all_logs_old = struct([]);

end

%% If an old pipeline exists, update the status of the jobs based on the
%% tag files that can be found


if flag_verbose
    fprintf('    Cleaning up job status ...\n');
end

job_status = cell(size(list_jobs));

for num_j = 1:length(list_jobs)
    name_job = list_jobs{num_j};
    if isfield(all_status_old,name_job)
        job_status{num_j} = all_status_old.(name_job);
    else
        job_status{num_j} = 'none';
    end
end

%% Update the job status using the tags that can be found in the log
%% folder
mask_inq = ismember(job_status,{'submitted','running'});
list_num_inq = find(mask_inq);
list_num_inq = list_num_inq(:)';
list_jobs_inq = list_jobs(mask_inq);
curr_status = psom_job_status(path_logs,list_jobs_inq,'session');

%% Remove the dependencies on finished jobs
mask_finished = ismember(curr_status,'finished');
list_num_finished = list_num_inq(mask_finished);
list_num_finished = list_num_finished(:)';

for num_j = list_num_finished
    
    name_job = list_jobs{num_j};
    text_log = sub_read_txt([path_logs filesep name_job '.log']);
    text_qsub_o = sub_read_txt([path_logs filesep name_job '.oqsub']);
    text_qsub_e = sub_read_txt([path_logs filesep name_job '.eqsub']);
    
    if ~isempty(text_qsub_o)&isempty(text_qsub_e)
        text_log = [text_log hat_qsub_o text_qsub_o hat_qsub_e text_qsub_e];
    end
    
    all_logs.(name_job) = text_log;
    job_status{num_j} = 'finished';
end

job_status_old = job_status;


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Stage 3 : Set up the 'restart' flags %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

flag_restart = (ismember(job_status_old,'none')|ismember(job_status_old,'failed')|ismember(job_status_old,'submitted'))';

if flag_verbose
    fprintf('\nSetting up the to-do list ...\n');
end

for num_j = 1:nb_jobs
    
    name_job = list_jobs{num_j};
    flag_restart_job = flag_restart(num_j);
    
    if strcmp(job_status_old{num_j},'failed')|strcmp(job_status_old{num_j},'exit')
        flag_restart_job = true;
        if flag_verbose
            fprintf('    The job %s had failed, it will be restarted.\n',name_job)
        end
    else
        %% If an old pipeline exists, check if the job has been modified
        if isfield(pipeline_old,name_job)
            if opt.flag_update
                flag_same = psom_cmp_var(pipeline_old.(name_job),pipeline.(name_job));
                if ~flag_same&&flag_verbose
                    fprintf('    The job %s has changed, it will be restarted.\n',name_job);
                end
            else
                flag_same = true;
                if (num_j == 1)&&flag_verbose
                    fprintf('    The OPT.FLAG_UPDATE is off, jobs are not going to be checked for updates.\n');
                end
            end
            if flag_same & strcmp(job_status_old{num_j},'none')
                fprintf('    The job %s has not yet been processed, it will be executed.\n',name_job);
                flag_restart_job = true;
            elseif flag_same & strcmp(job_status_old{num_j},'submitted')
                fprintf('    The job %s was not submitted successfully, it will be restarted.\n',name_job);
                flag_restart_job = true;
            end
            flag_restart_job = flag_restart_job||~flag_same;
        else
            flag_restart_job = true;
            if flag_verbose
                fprintf('    The job %s is new, it will be executed.\n',name_job)
            end
        end
        
        %% Check if the user did not force a restart on that job
        flag_force = psom_find_str_cell(name_job,opt.restart);
        if flag_force
            if flag_verbose
                fprintf('    User has manually forced to restart job %s.\n',name_job)
            end
            flag_restart_job = true;
        end
    end
    
    %% If the job is restarted, iteratively restart all its children and
    %% parents that produce necessary and missing input files
    if flag_restart_job
        
        mask_new_restart = false(size(flag_restart));
        mask_new_restart(num_j) = true;        
        flag_restart(num_j) = true;
        
        while any(mask_new_restart)
            
            %% restart the children of the restarted jobs that were not
            %% already planned to be restarted
            mask_new_restart2 = sub_find_children(mask_new_restart,graph_deps);
            mask_new_restart2 = mask_new_restart2 & ~flag_restart;           
            
            list_add = find(mask_new_restart2&~mask_new_restart);
            if ~isempty(list_add)
                if flag_verbose
                    fprintf('    The following job(s) will be restarted because they are children of restarted jobs :\n')
                end
                for num_a = 1:length(list_add)
                    if flag_verbose
                        fprintf('        %s\n',list_jobs{list_add(num_a)});
                    end
                end
            end
            
            %% restart the parents of the restarted jobs 
            mask_new_restart3 = sub_restart_parents(mask_new_restart,flag_restart,pipeline,list_jobs,deps,graph_deps,flag_verbose);
            mask_new_restart3 = mask_new_restart3 & ~flag_restart;
            
            list_add2 = find(mask_new_restart3&~mask_new_restart);
            if ~isempty(list_add2)
                if flag_verbose
                    fprintf('    The following job(s) will be restarted because they are producing missing files needed to run some of the restarted jobs :\n')
                end
                for num_a = 1:length(list_add2)
                    if flag_verbose
                        fprintf('        %s\n',list_jobs{list_add2(num_a)});
                    end
                end
            end
            
            %% Iterate the process on the children and parents that were newly assigned
            %% a restart flag            
            flag_restart(mask_new_restart2) = true;
            flag_restart(mask_new_restart3) = true;
            mask_new_restart = (mask_new_restart3 | mask_new_restart2)&~mask_new_restart;
            
        end
    end
end

%% Initialize the status :
%% Everything goes to 'none', except jobs that have a 'finished' status and
%% no restart tag

job_status = repmat({'none'},[nb_jobs 1]);

if flag_old_pipeline        
   
    if flag_verbose
        fprintf('    Initializing the new status (keeping finished jobs "as is")...\n');
    end
    
    flag_finished = ismember(job_status_old,'finished');
    flag_finished = flag_finished(:)';
    flag_finished = flag_finished & ~flag_restart;
    
    job_status(flag_finished) = repmat({'finished'},[sum(flag_finished) 1]);
    
else
    
    flag_finished = false([nb_jobs 1]);
    
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Stage 4: Save the pipeline description in the logs folder %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if flag_verbose
    fprintf('\nSaving the pipeline description in the logs folder ...\n');
end

if flag_pause
    fprintf('Any old description of the pipeline is going to be flushed (except for the log files of finished jobs).\nPress CTRL-C now to cancel or press any key to continue.\n');   
    pause
end

%% Create logs folder

if ~exist(path_logs,'dir')
    if flag_verbose
        fprintf('    Creating the logs folder ...\n');
    end

    [succ,messg,messgid] = psom_mkdir(path_logs);

    if succ == 0
        warning(messgid,messg);
    end
end

%% Save the jobs
if flag_verbose
    fprintf('    Saving the individual ''jobs'' file %s ...\n',file_jobs);
end

if exist(file_jobs,'file')
    pipeline_all = psom_merge_pipeline(pipeline_old,pipeline);
    if strcmp(gb_psom_language,'octave')
        sub_save_struct_fields(file_jobs,pipeline_all);
    else        
        save(file_jobs,'-struct','pipeline_all');
    end
else
    if strcmp(gb_psom_language,'octave')
        sub_save_struct_fields(file_jobs,pipeline);
    else
        save(file_jobs,'-struct','pipeline');
    end
end
copyfile(file_jobs,file_jobs_backup,'f');

%% Save the dependencies

if flag_verbose
    fprintf('    Saving the pipeline dependencies in %s...\n',file_pipeline);
end

if flag_old_pipeline    
    try
        load(file_pipeline,'history');
        history = char(history,[datestr(now) ' ' gb_psom_user ' on a ' gb_psom_OS ' system used PSOM v' gb_psom_version '>>>> The pipeline was restarted']);
    catch 
        history = [datestr(now) ' ' gb_psom_user ' on a ' gb_psom_OS ' system used PSOM v' gb_psom_version '>>>> Created a pipeline !'];
    end
        
else
    history = [datestr(now) ' ' gb_psom_user ' on a ' gb_psom_OS ' system used PSOM v' gb_psom_version '>>>> Created a pipeline !'];
end

path_work = opt.path_search;
save(file_pipeline,'history','deps','graph_deps','list_jobs','files_in','files_out','path_work')

%% Save the status

if flag_verbose
    fprintf('    Saving the ''status'' file %s ...\n',file_status);
end

flag_failed = ismember(job_status,'failed');
for num_j = 1:nb_jobs
    name_job = list_jobs{num_j};
    all_status.(name_job) = job_status{num_j};
end

if exist(file_status,'file')
    all_status = psom_merge_pipeline(all_status_old,all_status);
    if strcmp(gb_psom_language,'octave')
        sub_save_struct_fields(file_status,all_status);
    else
        save(file_status,'-struct','all_status');
    end
else
    if strcmp(gb_psom_language,'octave')
        sub_save_struct_fields(file_status,all_status);
    else
        save(file_status,'-struct','all_status');
    end
end
copyfile(file_status,file_status_backup,'f');

%% Save the logs 
if flag_verbose
    fprintf('    Saving the ''logs'' file %s ...\n',file_logs);
end

for num_j = 1:nb_jobs    
    name_job = list_jobs{num_j};    
    if flag_finished(num_j)||flag_failed(num_j)
        
        if ~isfield('all_logs',name_job)
            if exist('all_logs_old','var')&&isfield(all_logs_old,name_job)
                all_logs.(name_job) = all_logs_old.(name_job);
            else
                all_logs.(name_job) = '';
            end
        end        
    else        
        all_logs.(name_job) = '';        
    end
end

if exist(file_logs,'file')
    all_logs = psom_merge_pipeline(all_logs_old,all_logs);
    if strcmp(gb_psom_language,'octave')
        sub_save_struct_fields(file_logs,all_logs);
    else
        save(file_logs,'-struct','all_logs');
    end
else
    if strcmp(gb_psom_language,'octave')
        sub_save_struct_fields(file_logs,all_logs);
    else
        save(file_logs,'-struct','all_logs');
    end
end
copyfile(file_logs,file_logs_backup,'f');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Stage 5: Check for input files, generate output folders and clean old outputs %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if flag_verbose
    fprintf('\nClean up and check the file system for pipeline execution...\n');
end
%% Check if all the files necessary to complete each job of the pipeline 
%% can be found

if flag_verbose
    fprintf('    Checking if all the files necessary to complete the pipeline can be found ...\n');
end

flag_ready = true;
mask_unfinished = ~flag_finished;
list_num_unfinished = find(mask_unfinished);
list_num_unfinished = list_num_unfinished(:)';

for num_j = list_num_unfinished

    name_job = list_jobs{num_j};
    list_files_needed = files_in.(name_job);
    list_files_tobe = psom_files2cell(deps.(name_job));
    if ~isempty(list_files_needed)
        list_files_necessary = list_files_needed(~ismember(list_files_needed,list_files_tobe));
    else
        list_files_necessary = {};
    end

    flag_job_OK = true;
    
    for num_f = 1:length(list_files_necessary)
        
        if ~exist(list_files_necessary{num_f},'file')&~exist(list_files_necessary{num_f},'dir')&~isempty(list_files_necessary{num_f})&~strcmp(list_files_necessary{num_f},'gb_niak_omitted')

            if flag_job_OK
                msg_files = sprintf('        Job %s, the following file(s) are missing : %s',name_job,list_files_necessary{num_f});
            else
                msg_files = char(msg_files,sprintf(' , %s',list_files_necessary{num_f}));
            end
            flag_ready = false;
            flag_job_OK = false;

        end
    end
    
    if ~flag_job_OK        
        fprintf('%s\n',msg_files');        
    end
    
end

if ~flag_ready
    if flag_pause
        fprintf('\nThe input files of some jobs were found missing.\nPress CTRL-C now if you do not wish to run the pipeline or any key to continue anyway...\n');        
        pause        
    else
        warning('\nThe input files of some jobs were found missing.\n');
    end
end

%% Creating output folders 

if flag_verbose
    fprintf('    Creating output folders ...\n')
end

path_all = psom_files2cell(files_out);
path_all = cellfun (@fileparts,path_all,'UniformOutput',false);
path_all = unique(path_all);

for num_p = 1:length(path_all)
    path_f = path_all{num_p};
    [succ,messg,messgid] = psom_mkdir(path_f);
    if succ == 0
        warning(messgid,messg);
    end    
end

%% Removing old outputs
if flag_verbose
    fprintf('    Removing old outputs ...\n')
end
state_warning = warning;
warning('off','all');
for num_j = 1:length(list_jobs)    
    job_name = list_jobs{num_j};
    list_files = unique(files_out.(job_name));    
    if flag_clean&&~flag_finished(num_j)
        for num_f = 1:length(list_files)                             
            try, delete(list_files{num_f}); end,            
        end 
    end 
end
warning(state_warning(1).state,'all');

%% Clean up the log folders from old tag and log files

if flag_verbose
    fprintf('    Cleaning up old tags and logs from the logs folders ...\n')
end

delete([path_logs filesep '*.running']);
delete([path_logs filesep '*.failed']);
delete([path_logs filesep '*.finished']);
delete([path_logs filesep '*.exit']);
delete([path_logs filesep '*.log']);
delete([path_logs filesep '*.oqsub']);
delete([path_logs filesep '*.eqsub']);

if exist([path_logs 'tmp'],'dir')
    if strcmp(gb_psom_language,'octave')
        instr_rm = ['rm -rf ' path_logs 'tmp'];
        [succ,msg] = system(instr_rm);
    else
        [succ,msg] = rmdir([path_logs 'tmp'],'s');        
    end
    if ~succ
        warning('Could not remove the temporary folder %s. Check for permissions.',[path_logs 'tmp']);
    end            
end

%% Done !
if flag_verbose
    fprintf('\nThe pipeline has been successfully initialized !\n')
end

%%%%%%%%%%%%%%%%%%
%% Subfunctions %%
%%%%%%%%%%%%%%%%%%

%% Save the fields of a structure as independent variables in a .mat file
function sub_save_struct_fields(file_name,var_struct,flag_append)

if nargin < 3
    flag_append = false;
end

gb_psom_list_fields = fieldnames(var_struct);

for gb_psom_num_f = 1:length(gb_psom_list_fields)
    gb_psom_field_name = gb_psom_list_fields{gb_psom_num_f};
    eval([gb_psom_field_name ' = var_struct.(gb_psom_field_name);']);
end

clear gb_psom_num_f gb_psom_list_fields var_struct gb_psom_field_name argn

if flag_append
    eval(['clear file_name flag_append; save -append ' file_name ' [a-zA-Z]*']);
else
    eval(['clear file_name flag_append; save ' file_name ' [a-zA-Z]*']);
end

%% Read a text file
function str_txt = sub_read_txt(file_name)

if exist(file_name,'file')
    hf = fopen(file_name,'r');
    str_txt = fread(hf,Inf,'uint8=>char')';
    fclose(hf);
else
    str_txt = '';
end

%% find all the jobs that depend on one job 
function mask_child = sub_find_children(mask,graph_deps)
% GRAPH_DEPS(J,K) == 1 if and only if JOB K depends on JOB J. GRAPH_DEPS =
% 0 otherwise. This (ugly but reasonably fast) recursive code will work
% only if the directed graph defined by GRAPH_DEPS is acyclic.

if max(double(mask))>0
    mask_child = max(graph_deps(mask,:),[],1);    
else
    mask_child = false(size(mask));
end

%% Test if the inputs of some jobs are missing, and set restart
%% flags on the jobs that can produce those inputs.
function flag_parent = sub_restart_parents(flag_restart_new,flag_restart,pipeline,list_jobs,deps,graph_deps,flag_verbose)

list_restart = find(flag_restart_new);

flag_parent = false(size(flag_restart_new));

for num_j = list_restart % loop over jobs that need to be restarted
    
    name_job = list_jobs{num_j};
    
    % Pick up parents that are not already scheduled to be restarted
    list_num_parent = find(graph_deps(:,num_j)&~flag_restart_new(:)&~flag_restart(:));     
    
    for num_l = list_num_parent'
        
        name_job2 = list_jobs{num_l};
        flag_OK = true;
        
        for num_f = 1:length(deps.(name_job).(name_job2))
            flag_file = exist(deps.(name_job).(name_job2){num_f},'file');
            
            if ~flag_file
                if flag_verbose
                    if flag_OK
                        fprintf('    The following file(s) produced by the job %s are missing to process job %s.\n',name_job2,name_job);
                        fprintf('        %s\n',deps.(name_job).(name_job2){num_f});
                    else
                        fprintf('        %s\n',deps.(name_job).(name_job2){num_f});
                    end
                end
            end
            flag_OK = flag_OK & flag_file;
        end
        
        if ~flag_OK
            flag_parent(num_l) = true;
        end
    end
    
end