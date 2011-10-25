function [] = psom_run_script(cmd,opt)
% Run an Octave/Matlab command using various shell-based execution mechanisms.
%
% SYNTAX:
% [failed,MSG] = PSOM_RUN_SCRIPT(CMD,OPT)
%
%_________________________________________________________________________
% INPUTS:
%
% CMD
%    (string) A Matlab/Octave command. If it is empty, it is still possible 
%    to run a command using OPT.SHELL_OPTIONS below.
%
% OPT
%    (structure) describes how to execute the command.
%
%    MODE
%        (string) the execution mechanism. Available 
%        options :
%        'session'    : current Matlab session.
%        'background' : background execution, non-unlogin-proofed 
%                       (asynchronous system call).
%        'batch'      : background execution, unlogin-proofed ('at' in 
%                       UNIX, start in WINDOWS.
%        'qsub'       : remote execution using qsub (torque, SGE, PBS).
%        'msub'       : remote execution using msub (MOAB)
%
%    SHELL_OPTIONS
%       (string, default GB_PSOM_SHELL_OPTIONS defined in PSOM_GB_VARS)
%       some commands that will be added at the begining of the shell
%       script. This can be used to set important variables, or source an 
%       initialization script.
%
%    QSUB_OPTIONS
%        (string, GB_PSOM_QSUB_OPTIONS defined in PSOM_GB_VARS)
%        This field can be used to pass any argument when submitting a
%        job with qsub/msub. For example, '-q all.q@yeatman,all.q@zeus'
%        will force qsub/msub to only use the yeatman and zeus
%        workstations in the all.q queue. It can also be used to put
%        restrictions on the minimum avalaible memory, etc.
%
%    COMMAND_MATLAB
%        (string, default GB_PSOM_COMMAND_MATLAB or
%        GB_PSOM_COMMAND_OCTAVE depending on the current environment)
%        how to invoke matlab (or OCTAVE).
%        You may want to update that to add the full path of the command.
%        The defaut for this field can be set using the variable
%        GB_PSOM_COMMAND_MATLAB/OCTAVE in the file PSOM_GB_VARS.
%
%    INIT_MATLAB
%        (string, default '') a matlab command (multiple commands can
%        actually be passed using comma separation) that will be
%        executed at the begining of any matlab/Octave job. That 
%        mechanism can be used, e.g., to set up the state of the random 
%        generation number.
%
%    FLAG_DEBUG
%        (boolean, default false) if FLAG_DEBUG is true, the program
%        prints additional information for debugging purposes.
%
%_________________________________________________________________________
% OUTPUTS:
%
% FLAG_FAILED
%    (boolean) FLAG_FAILED is true if the job has failed. This happens if 
%    the command of the job generated an error, or if one of the output 
%    files of the job was not successfully generated.
%
% MSG
%    (string) the output of the job.
%         
% _________________________________________________________________________
% COMMENTS:
%
% The function will automatically use Matlab (resp. Octave) to execute the 
% commmand when invoked from Matlab (resp. Octave).  
%
% Copyright (c) Pierre Bellec, Montreal Neurological Institute, 2008-2010.
% Departement d'informatique et de recherche operationnelle
% Centre de recherche de l'institut de Geriatrie de Montreal
% Universite de Montreal, 2010-2011.
% Maintainer : pierre.bellec@criugm.qc.ca
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

psom_gb_vars

%% Check syntax
if nargin<2
    error('SYNTAX: [] = PSOM_RUN_SCRIPT(CMD,OPT). Type ''help psom_run_script'' for more info.')
end

%% Options
list_fields    = {'init_matlab'       , 'flag_debug' , 'shell_options'       , 'command_matlab' , 'mode' , 'qsub_options'       };
list_defaults  = {gb_psom_init_matlab , true         , gb_psom_shell_options , ''               , NAN    , gb_psom_qsub_options };
opt = psom_struct_defaults(opt,list_fields,list_defaults);

if isempty(opt.command_matlab)
    if strcmp(gb_psom_language,'matlab')
        opt.command_matlab = gb_psom_command_matlab;
    else
        opt.command_matlab = gb_psom_command_octave;
    end
end

%% Test the the requested mode of execution of jobs exists
if ~ismember(opt.mode,{'session','background','batch','qsub','msub'})
    error('%s is an unknown mode of pipeline execution. Sorry dude, I must quit ...',opt.mode);
end

switch gb_psom_language
    case 'matlab'
        if ispc
            opt_matlab = '-automation -nodesktop -r';
        else
            opt_matlab = '-nosplash -nodesktop -r';
        end        
    case 'octave'
        opt_matlab = '--silent --eval';       
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% The pipeline processing starts now  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Generic messages
hat_qsub_o = sprintf('\n\n*****************\nOUTPUT QSUB\n*****************\n');
hat_qsub_e = sprintf('\n\n*****************\nERROR QSUB\n*****************\n');

%% Generating file names
[path_logs,name_pipeline,ext_pl] = fileparts(file_pipeline);
file_pipe_running   = [ path_logs filesep name_pipeline '.lock'               ];
file_pipe_log       = [ path_logs filesep name_pipeline '_history.txt'        ];
file_manager_opt    = [ path_logs filesep name_pipeline '_manager_opt.mat'    ];
file_logs           = [ path_logs filesep name_pipeline '_logs.mat'           ];
file_logs_backup    = [ path_logs filesep name_pipeline '_logs_backup.mat'    ];
file_status         = [ path_logs filesep name_pipeline '_status.mat'         ];
file_status_backup  = [ path_logs filesep name_pipeline '_status_backup.mat'  ];
file_jobs           = [ path_logs filesep name_pipeline '_jobs.mat'           ];
file_profile        = [ path_logs filesep name_pipeline '_profile.mat'        ];
file_profile_backup = [ path_logs filesep name_pipeline '_profile_status.mat' ];

logs    = load( file_logs    );
status  = load( file_status  );
profile = load( file_profile );

%% If necessary, create a temporary subfolder in the "logs" folder
path_tmp = [path_logs filesep 'tmp'];
if exist(path_tmp,'dir')
    delete([path_tmp '*']);
else
    mkdir(path_tmp);
end

%% Check for the existence of the pipeline
if ~exist(file_pipeline,'file') % Does the pipeline exist ?
    error('Could not find the pipeline file %s. You first need to initialize the pipeline using PSOM_PIPELINE_INIT !',file_pipeline);
end

%% Create a running tag on the pipeline
str_now = datestr(clock);
save(file_pipe_running,'str_now');

%% If specified, start the pipeline manager in the background
if ismember(opt.mode_pipeline_manager,{'batch','qsub','msub'})
    
    % save the options of the pipeline manager
    opt.mode_pipeline_manager = 'session';
    save(file_manager_opt,'opt');
    
    if strcmp(opt.mode_pipeline_manager,'batch')
        if ispc 
            mode_pipeline_manager = 'start';
        else
            mode_pipeline_manager = 'at';
        end
    end
    
    if flag_verbose
        fprintf('I am sending the pipeline manager in the background using the ''%s'' command.\n',mode_pipeline_manager)
    end
            
    if ~isempty(opt.init_matlab)
        instr_job = sprintf('%s %s "%s load(''%s'',''path_work''), if ~strcmp(path_work,''gb_psom_omitted''), path(path_work), end, load(''%s''), psom_pipeline_process(''%s'',opt),exit"\n',command_matlab,opt_matlab,opt.init_matlab,file_pipeline,file_manager_opt,file_pipeline);
    else
        instr_job = sprintf('%s %s "load(''%s'',''path_work''), if ~strcmp(path_work,''gb_psom_omitted''), path(path_work), end, load(''%s''), psom_pipeline_process(''%s'',opt),exit"\n',command_matlab,opt_matlab,file_pipeline,file_manager_opt,file_pipeline);
    end
        
    if ~isempty(opt.shell_options)
        instr_job = sprintf('%s\n%s',opt.shell_options,instr_job);
    end
    
    if flag_debug
        if ispc
            % for windows
            fprintf('\n\nThe following batch script is used to run the pipeline manager in the background :\n%s\n\n',instr_job);
        else
            fprintf('\n\nThe following shell script is used to run the pipeline manager in the background :\n%s\n\n',instr_job);
        end
        fprintf('The pipeline manager is about to start up now. Press CTRL-C to abort.');
        pause
    end
    
    if ispc
        file_shell = [path_tmp filesep 'pipeline_manager.bat'];
    else
        file_shell = [path_tmp filesep 'pipeline_manager.sh'];
    end
    
    hf = fopen(file_shell,'w');
    fprintf(hf,'%s',instr_job);
    fclose(hf);
    
    file_qsub_o = [path_logs filesep name_pipeline '.oqsub'];
    file_qsub_e = [path_logs filesep name_pipeline '.eqsub'];
    switch mode_pipeline_manager  
        case 'qsub'            
            instr_batch = ['qsub -e ' file_qsub_e ' -o ' file_qsub_o ' -N ' name_pipeline(1:min(15,length(name_pipeline))) ' ' opt.qsub_options ' ' file_shell];            
        case 'msub'            
            instr_batch = ['msub -e ' file_qsub_e ' -o ' file_qsub_o ' -N ' name_pipeline(1:min(15,length(name_pipeline))) ' ' opt.qsub_options ' ' file_shell];            
        otherwise            
            switch gb_psom_OS
                case 'windows'
                    instr_batch = sprintf('start /min %s',file_shell);
                otherwise
                    instr_batch = ['at -f ' file_shell ' now'];
            end
            
    end
    
    [fail,msg] = system(instr_batch);
    if fail~=0
        if ispc
            % This is windows
            error('Something went bad when sending the pipeline in the background. The command was : %s. The error message was : %s',instr_batch,msg)
        else
            error('Something went bad when sending the pipeline in the background. The command was : %s. The error message was : %s',instr_batch,msg)
        end
    end
    if flag_debug
        fprintf('\n\nThe call to at/qsub/msub produced the following message :\n%s\n\n',msg);
    end
    
    return
    
end

% a try/catch block is used to clean temporary file if the user is
% interrupting the pipeline of if an error occurs
try    
    
    %% If the pipeline manager is executed in the session, open the log
    %% file
    if strcmp(gb_psom_language,'matlab');
        hfpl = fopen(file_pipe_log,'a');
    else
        hfpl = file_pipe_log;
    end
    
    %% Print general info about the pipeline
    msg_line1 = sprintf('The pipeline %s is now being processed.',name_pipeline);
    msg_line2 = sprintf('Started on %s',datestr(clock));
    msg_line3 = sprintf('user: %s, host: %s, system: %s',gb_psom_user,gb_psom_localhost,gb_psom_OS);
    size_msg = max([size(msg_line1,2),size(msg_line2,2),size(msg_line3,2)]);
    msg = sprintf('%s\n%s\n%s',msg_line1,msg_line2,msg_line3);
    stars = repmat('*',[1 size_msg]);
    if flag_verbose
        fprintf('\n%s\n%s\n%s\n',stars,msg,stars);
    end
    sub_add_line_log(hfpl,sprintf('\n%s\n%s\n%s\n',stars,msg,stars));
    
    %% Load the pipeline
    load(file_pipeline,'list_jobs','graph_deps','files_in');                
    
    %% update dependencies
    mask_finished = false([length(list_jobs) 1]);
    for num_j = 1:length(list_jobs)
        mask_finished(num_j) = strcmp(status.(list_jobs{num_j}),'finished');
    end
    graph_deps(mask_finished,:) = 0;
    mask_deps = max(graph_deps,[],1)>0;
    mask_deps = mask_deps(:);
    
    %% Initialize the to-do list
    mask_todo = false([length(list_jobs) 1]);
    for num_j = 1:length(list_jobs)
        mask_todo(num_j) = strcmp(status.(list_jobs{num_j}),'none');
    end    
    mask_done = ~mask_todo;
    
    mask_failed = false([length(list_jobs) 1]);
    for num_j = 1:length(list_jobs)
        mask_failed(num_j) = strcmp(status.(list_jobs{num_j}),'failed');
    end    
    list_num_failed = find(mask_failed);
    list_num_failed = list_num_failed(:)';
    for num_j = list_num_failed
        mask_child = false([1 length(mask_todo)]);
        mask_child(num_j) = true;
        mask_child = sub_find_children(mask_child,graph_deps);
        mask_todo(mask_child) = false; % Remove the children of the failed job from the to-do list
    end
    
    mask_running = false(size(mask_done));
    
    %% Initialize miscallenaous variables
    nb_queued   = 0;                   % Number of queued jobs
    nb_todo     = sum(mask_todo);      % Number of to-do jobs
    nb_finished = sum(mask_finished);  % Number of finished jobs
    nb_failed   = sum(mask_failed);    % Number of failed jobs
    nb_checks   = 0;                   % Number of checks to print a points
    nb_points   = 0;                   % Number of printed points
    
    lmax = 0;
    for num_j = 1:length(list_jobs)
        lmax = max(lmax,length(list_jobs{num_j}));
    end   

    %% The pipeline manager really starts here
    while ((max(mask_todo)>0) || (max(mask_running)>0)) && exist(file_pipe_running,'file')

        %% Update logs & status
        save(file_logs           ,'-struct','logs');
        save(file_logs_backup    ,'-struct','logs');
        save(file_status         ,'-struct','status');
        save(file_status_backup  ,'-struct','status');        
        save(file_profile        ,'-struct','profile');
        save(file_profile_backup ,'-struct','profile');
        flag_nothing_happened = true;
        
        %% Update the status of running jobs
        list_num_running = find(mask_running);
        list_num_running = list_num_running(:)';
        list_jobs_running = list_jobs(list_num_running);
        new_status_running_jobs = psom_job_status(path_logs,list_jobs_running,opt.mode);
        pause(time_cool_down); % pause for a while to let the system finish to write eqsub and oqsub files (useful in 'qsub' mode).
        
        %% Loop over running jobs to check the new status
        num_l = 0;
        for num_j = list_num_running
            num_l = num_l+1;
            name_job = list_jobs{num_j};
            flag_changed = ~strcmp(status.(name_job),new_status_running_jobs{num_l});
            
            if flag_changed
                
                if flag_nothing_happened % if nothing happened before...
                    %% Reset the 'dot counter'
                    flag_nothing_happened = false;
                    nb_checks = 0;
                    if nb_points>0
                        if flag_verbose
                            fprintf('\n');
                        end
                        sub_add_line_log(hfpl,sprintf('\n'));
                    end
                    nb_points = 0;
                end
                
                % update status in the status file                
                status.(name_job) = new_status_running_jobs{num_l};
                
                if strcmp(status.(name_job),'exit') % the script crashed ('exit' tag)
                    if flag_verbose
                        fprintf('%s - The script of job %s terminated without generating any tag, I guess we will count that one as failed.\n',datestr(clock),name_job);
                    end
                    sub_add_line_log(hfpl,sprintf('%s - The script of job %s terminated without generating any tag, I guess we will count that one as failed.\n',datestr(clock),name_job));;
                    status.(name_job) = 'failed';
                    nb_failed = nb_failed + 1;
                end
                
                if strcmp(status.(name_job),'failed')||strcmp(status.(name_job),'finished')
                    %% for finished or failed jobs, transfer the individual
                    %% test log files to the matlab global logs structure
                    nb_queued = nb_queued - 1;
                    text_log    = sub_read_txt([path_logs filesep name_job '.log']);
                    text_qsub_o = sub_read_txt([path_logs filesep name_job '.oqsub']);
                    text_qsub_e = sub_read_txt([path_logs filesep name_job '.eqsub']);                    
                    if isempty(text_qsub_o)&&isempty(text_qsub_e)
                        logs.(name_job) = text_log;                        
                    else
                        logs.(name_job) = [text_log hat_qsub_o text_qsub_o hat_qsub_e text_qsub_e];
                    end
                    %% Update profile for the jobs
                    profile.(name_job) = load([path_logs filesep name_job '.profile.mat']);
                    sub_clean_job(path_logs,name_job); % clean up all tags & log                    
                end
                
                switch status.(name_job)
                    
                    case 'failed' % the job has failed, too bad !

                        nb_failed = nb_failed + 1;   
                        msg = sprintf('%s - The job %s%s has failed                     ',datestr(clock),name_job,repmat(' ',[1 lmax-length(name_job)]));
                        if flag_verbose
                            fprintf('%s (%i running / %i failed / %i finished / %i left).\n',msg,nb_queued,nb_failed,nb_finished,nb_todo);
                        end
                        sub_add_line_log(hfpl,sprintf('%s (%i running / %i failed / %i finished / %i left).\n',msg,nb_queued,nb_failed,nb_finished,nb_todo));
                        mask_child = false([1 length(mask_todo)]);
                        mask_child(num_j) = true;
                        mask_child = sub_find_children(mask_child,graph_deps);
                        mask_todo(mask_child) = false; % Remove the children of the failed job from the to-do list

                    case 'finished'

                        nb_finished = nb_finished + 1;                        
                        msg = sprintf('%s - The job %s%s has been successfully completed',datestr(clock),name_job,repmat(' ',[1 lmax-length(name_job)]));
                        if flag_verbose
                            fprintf('%s (%i running / %i failed / %i finished / %i left).\n',msg,nb_queued,nb_failed,nb_finished,nb_todo);
                        end
                        sub_add_line_log(hfpl,sprintf('%s (%i running / %i failed / %i finished / %i left).\n',msg,nb_queued,nb_failed,nb_finished,nb_todo));
                        graph_deps(num_j,:) = 0; % update dependencies

                end
                
            end % if flag changed
        end % loop over running jobs
        
        if ~flag_nothing_happened % if something happened ...
            
            %% update the to-do list
            mask_done(mask_running) = ismember(new_status_running_jobs,{'finished','failed','exit'});
            mask_todo(mask_running) = mask_todo(mask_running)&~mask_done(mask_running);
            
            %% Update the dependency mask
            mask_deps = max(graph_deps,[],1)>0;
            mask_deps = mask_deps(:);
            
            %% Finally update the list of currently running jobs
            mask_running(mask_running) = mask_running(mask_running)&~mask_done(mask_running);
            
        end
        
        %% Time to (try to) submit jobs !!
        list_num_to_run = find(mask_todo&~mask_deps);
        num_jr = 1;
        
        while (nb_queued < max_queued) && (num_jr <= length(list_num_to_run))
            
            if flag_nothing_happened % if nothing happened before...
                %% Reset the 'dot counter'
                flag_nothing_happened = false;
                nb_checks = 0;
                if nb_points>0
                    if flag_verbose
                        fprintf('\n');
                    end
                    sub_add_line_log(hfpl,sprintf('\n'));
                end
                nb_points = 0;
            end
            
            %% Pick up a job to run
            num_job = list_num_to_run(num_jr);
            num_jr = num_jr + 1;
            name_job = list_jobs{num_job};
            file_job = [path_logs filesep name_job '.mat'];
            file_log = [path_logs filesep name_job '.log'];
            mask_todo(num_job) = false;
            mask_running(num_job) = true;
            nb_queued = nb_queued + 1;
            nb_todo = nb_todo - 1;
            status.(name_job) = 'submitted';
            msg = sprintf('%s - The job %s%s has been submitted to the queue',datestr(clock),name_job,repmat(' ',[1 lmax-length(name_job)]));            
            if flag_verbose
                fprintf('%s (%i running / %i failed / %i finished / %i left).\n',msg,nb_queued,nb_failed,nb_finished,nb_todo);
            end
            sub_add_line_log(hfpl,sprintf('%s (%i running / %i failed / %i finished / %i left).\n',msg,nb_queued,nb_failed,nb_finished,nb_todo));
                        
            %% Create a temporary shell scripts for 'batch' or 'qsub' modes
            if ~strcmp(opt.mode,'session')
                if ~isempty(opt.init_matlab)
                    if ~ismember(opt.init_matlab(end),{',',';'})
                        opt.init_matlab = [opt.init_matlab ','];
                    end
                end
                        
                if ~isempty(opt.init_matlab)
                    instr_job = sprintf('%s %s "%s load(''%s'',''path_work''), if ~strcmp(path_work,''gb_psom_omitted''), path(path_work), end, psom_run_job(''%s''),exit">%s\n',command_matlab,opt_matlab,opt.init_matlab,file_pipeline,file_job,file_log);
                else
                    instr_job = sprintf('%s %s "load(''%s'',''path_work''), if ~strcmp(path_work,''gb_psom_omitted''), path(path_work), end, psom_run_job(''%s''),exit">%s\n',command_matlab,opt_matlab,file_pipeline,file_job,file_log);
                end
                                                
                if ~isempty(opt.shell_options)
                    instr_job = sprintf('%s\n%s',opt.shell_options,instr_job);
                end
                
                if ispc
                    % this is windows
                    file_shell = [path_tmp filesep name_job '.bat'];
                else
                    file_shell = [path_tmp filesep name_job '.sh'];
                end
                
                file_exit = [path_logs filesep name_job '.exit'];
                hf = fopen(file_shell,'w');
                if ispc
                    % this is windows
                    fprintf(hf,'%s\ntype nul > %s\nexit\n',instr_job,file_exit);
                else
                    fprintf(hf,'%s\ntouch %s',instr_job,file_exit);
                end
                fclose(hf);
                
            end
            
            %% run the job
            switch opt.mode
                
                case 'session'
                    
                    diary(file_log)
                    psom_run_job(file_job);
                    diary off
                    
                case 'batch'
                    
                    if ispc
                        instr_batch = ['start /min ' file_shell];
                    else
                        instr_batch = ['at -f ' file_shell ' now'];
                    end
                    
                    [fail,msg] = system(instr_batch);
                    if flag_debug||(fail~=0)
                        fprintf('The batch command was : %s\n The feedback was : %s\n',instr_batch,msg);
                        sub_add_line_log(hfpl,sprintf('The batch command was : %s\n The feedback was : %s\n',instr_batch,msg));
                    end
                    if fail~=0
                        error('Something went bad with the batch command.')
                    end
                                       
                case 'qsub'
                    
                    file_qsub_o = [path_logs filesep name_job '.oqsub'];
                    file_qsub_e = [path_logs filesep name_job '.eqsub'];
                    
                    instr_qsub = ['qsub -e ' file_qsub_e ' -o ' file_qsub_o ' -N ' name_job(1:min(15,length(name_job))) ' ' opt.qsub_options ' ' file_shell];
                    if flag_debug
                        [fail,msg] = system(instr_qsub);
                        fprintf('The qsub command was : %s.\n The feedback was : %s\n',instr_qsub,msg);
                        sub_add_line_log(hfpl,sprintf('The qsub command was : %s.\n The feedback was : %s\n',instr_qsub,msg));
                        if fail~=0
                            error('Something went bad with the qsub command.')
                        end
                    else
                        
                        [fail,msg] = system([instr_qsub '&']);
                        
                        if fail~=0
                            error('Something went bad with the qsub command. The command was : %s . The error message was : %s',instr_qsub,msg)
                        end
                    end
                case 'msub'
                    
                    file_qsub_o = [path_logs filesep name_job '.oqsub'];
                    file_qsub_e = [path_logs filesep name_job '.eqsub'];
                    
                    instr_qsub = ['msub -e ' file_qsub_e ' -o ' file_qsub_o ' -N ' name_job(1:min(15,length(name_job))) ' ' opt.qsub_options ' ' file_shell];
                    if flag_debug
                        [fail,msg] = system(instr_qsub);
                        fprintf('The msub command was : %s.\n The feedback was : %s\n',instr_qsub,msg);
                        sub_add_line_log(hfpl,sprintf('The msub command was : %s.\n The feedback was : %s\n',instr_qsub,msg));
                        if fail~=0
                            error('Something went bad with the msub command.')
                        end
                    else
                        
                        [fail,msg] = system([instr_qsub '&']);
                        
                        if fail~=0
                            error('Something went bad with the msub command. The command was : %s . The error message was : %s',instr_qsub,msg)
                        end
                    end
            end % switch mode
        end % submit jobs
        
        pause(time_between_checks); % To avoid wasting resources, wait a bit before re-trying to submit jobs
        
        if nb_checks >= nb_checks_per_point
            nb_checks = 0;
            if flag_verbose
                fprintf('.');
            end
            sub_add_line_log(hfpl,sprintf('.'));
            nb_points = nb_points+1;
        else
            nb_checks = nb_checks+1;
        end
        
    end % While there are jobs to do
    
catch
    
    errmsg = lasterror;        
    fprintf('\n\n******************\nSomething went bad ... the pipeline has FAILED !\nThe last error message occured was :\n%s\n',errmsg.message);
    
    sub_add_line_log(hfpl,sprintf('\n\n******************\nSomething went bad ... the pipeline has FAILED !\nThe last error message occured was :\n%s\n',errmsg.message));
    if isfield(errmsg,'stack')
        for num_e = 1:length(errmsg.stack)
            fprintf('File %s at line %i\n',errmsg.stack(num_e).file,errmsg.stack(num_e).line);
            sub_add_line_log(hfpl,sprintf('File %s at line %i\n',errmsg.stack(num_e).file,errmsg.stack(num_e).line));
        end
    end
    if exist('file_pipe_running','var')
        if exist(file_pipe_running,'file')
            delete(file_pipe_running); % remove the 'running' tag
        end
    end
    
    %% Close the log file
    if strcmp(gb_psom_language,'matlab')
        fclose(hfpl);
    end
    return
end

%% Update the final status
save(file_logs           ,'-struct','logs');
save(file_logs_backup    ,'-struct','logs');
save(file_status         ,'-struct','status');
save(file_status_backup  ,'-struct','status');
save(file_profile        ,'-struct','profile');
save(file_profile_backup ,'-struct','profile');

%% Print general info about the pipeline
msg_line1 = sprintf('The processing of the pipeline is terminated.');
msg_line2 = sprintf('See report below for job completion status.');
msg_line3 = sprintf('%s',datestr(now));
size_msg = max([size(msg_line1,2),size(msg_line2,2)]);
msg = sprintf('%s\n%s\n%s',msg_line1,msg_line2,msg_line3);
stars = repmat('*',[1 size_msg]);
if flag_verbose
    fprintf('\n%s\n%s\n%s\n',stars,msg,stars);
end
sub_add_line_log(hfpl,sprintf('\n%s\n%s\n%s\n',stars,msg,stars));

%% Report if the lock file was manually removed
if exist('file_pipe_running','var')
    if ~exist(file_pipe_running,'file')
        fprintf('The pipeline manager was interrupted because the .lock file was manually deleted.\n');
        sub_add_line_log(hfpl,sprintf('The pipeline manager was interrupted because the .lock file was manually deleted.\n'));
    end    
end

%% Print a list of failed jobs
mask_failed = false([length(list_jobs) 1]);
for num_j = 1:length(list_jobs)
    mask_failed(num_j) = strcmp(status.(list_jobs{num_j}),'failed');
end
mask_todo = false([length(list_jobs) 1]);
for num_j = 1:length(list_jobs)
    mask_todo(num_j) = strcmp(status.(list_jobs{num_j}),'none');
end
list_num_failed = find(mask_failed);
list_num_failed = list_num_failed(:)';
list_num_none = find(mask_todo);
list_num_none = list_num_none(:)';
flag_any_fail = ~isempty(list_num_failed);

if flag_any_fail
    if length(list_num_failed) == 1
        if flag_verbose
            fprintf('The execution of the following job has failed :\n\n    ');
        end
        sub_add_line_log(hfpl,sprintf('The execution of the following job has failed :\n\n    '));
    else
        if flag_verbose
            fprintf('The execution of the following jobs have failed :\n\n    ');
        end
        sub_add_line_log(hfpl,sprintf('The execution of the following jobs have failed :\n\n    '));
    end
    for num_j = list_num_failed
        name_job = list_jobs{num_j};
        if flag_verbose
            fprintf('%s ; ',name_job);
        end
        sub_add_line_log(hfpl,sprintf('%s ; ',name_job));
    end
    fprintf('\n\n');
    sub_add_line_log(hfpl,sprintf('\n\n'));
    if flag_verbose
        fprintf('More infos can be found in the individual log files. Use the following command to display these logs :\n\n    psom_pipeline_visu(''%s'',''log'',JOB_NAME)\n\n',path_logs);
    end
    sub_add_line_log(hfpl,sprintf('More infos can be found in the individual log files. Use the following command to display these logs :\n\n    psom_pipeline_visu(''%s'',''log'',JOB_NAME)\n\n',path_logs));
end

%% Print a list of jobs that could not be processed
if ~isempty(list_num_none)
    if length(list_num_none) == 1
        if flag_verbose
            fprintf('The following job has not been processed due to a dependence on a failed job or the interruption of the pipeline manager :\n\n    ');
        end
        sub_add_line_log(hfpl,sprintf('The following job has not been processed due to a dependence on a failed job or the interruption of the pipeline manager :\n\n    '));
    else
        if flag_verbose
            fprintf('The following jobs have not been processed due to a dependence on a failed job or the interruption of the pipeline manager :\n\n    ');
        end
        sub_add_line_log(hfpl,sprintf('The following jobs have not been processed due to a dependence on a failed job or the interruption of the pipeline manager :\n\n    '));
    end
    for num_j = list_num_none
        name_job = list_jobs{num_j};
        if flag_verbose
            fprintf('%s ; ',name_job);
        end
        sub_add_line_log(hfpl,sprintf('%s ; ',name_job));
    end
    if flag_verbose
        fprintf('\n\n');
    end
    sub_add_line_log(hfpl,sprintf('\n\n'));
end

%% Give a final one-line summary of the processing
if flag_any_fail
    if flag_verbose
        fprintf('All jobs have been processed, but some jobs have failed.\nYou may want to restart the pipeline latter if you managed to fix the problems.\n');
    end
    sub_add_line_log(hfpl,sprintf('All jobs have been processed, but some jobs have failed.\nYou may want to restart the pipeline latter if you managed to fix the problems.\n'));
else
    if isempty(list_num_none)
        if flag_verbose
            fprintf('All jobs have been successfully completed.\n');
        end
        sub_add_line_log(hfpl,sprintf('All jobs have been successfully completed.\n'));
    end
end

if ismember(opt.mode_pipeline_manager,{'qsub','batch'})&& strcmp(gb_psom_language,'octave')   
    sub_add_line_log(hfpl,sprintf('Press CTRL-C to go back to Octave.\n'));
end

%% Close the log file
if strcmp(gb_psom_language,'matlab')
    fclose(hfpl);
end

if exist('file_pipe_running','var')
    if exist(file_pipe_running,'file')
        delete(file_pipe_running); % remove the 'running' tag
    end
end

%%%%%%%%%%%%%%%%%%
%% subfunctions %%
%%%%%%%%%%%%%%%%%%

%% Find the children of a job
function mask_child = sub_find_children(mask,graph_deps)
% GRAPH_DEPS(J,K) == 1 if and only if JOB K depends on JOB J. GRAPH_DEPS =
% 0 otherwise. This (ugly but reasonably fast) recursive code will work
% only if the directed graph defined by GRAPH_DEPS is acyclic.
% MASK_CHILD(NUM_J) == 1 if the job NUM_J is a children of one of the job
% in the boolean mask MASK and the job is in MASK_TODO.
% This last restriction is used to speed up computation.

if max(double(mask))>0
    mask_child = max(graph_deps(mask,:),[],1)>0;    
    mask_child_strict = mask_child & ~mask;
else
    mask_child = false(size(mask));
end

if any(mask_child)
    mask_child = mask_child | sub_find_children(mask_child_strict,graph_deps);
end

%% Read a text file
function str_txt = sub_read_txt(file_name)

hf = fopen(file_name,'r');
if hf == -1
    str_txt = '';
else
    str_txt = fread(hf,Inf,'uint8=>char')';
    fclose(hf);    
end

%% Clean up the tags and logs associated with a job
function [] = sub_clean_job(path_logs,name_job)

files{1} = [path_logs filesep name_job '.log'];
files{2} = [path_logs filesep name_job '.finished'];
files{3} = [path_logs filesep name_job '.failed'];
files{4} = [path_logs filesep name_job '.running'];
files{5} = [path_logs filesep name_job '.exit'];
files{6} = [path_logs filesep name_job '.eqsub'];
files{7} = [path_logs filesep name_job '.oqsub'];
files{8} = [path_logs filesep name_job '.profile.mat'];
files{9} = [path_logs filesep 'tmp' filesep name_job '.sh'];

for num_f = 1:length(files)
    if psom_exist(files{num_f});
        delete(files{num_f});
    end
end

function [] = sub_add_line_log(file_write,str_write);

if ischar(file_write)
    hf = fopen(file_write,'a');
    fprintf(hf,'%s',str_write);
    fclose(hf);
else
    fprintf(file_write,'%s',str_write);
end