require 'json'

class GitlabHookController < SysController

  GIT_BIN = Redmine::Configuration[:scm_git_command] || 'git'


  def index
    if request.post?
      repository = find_repository
      p repository.inspect
      git_success = true
      if repository
        # Fetch the changes from GitLab
        if Setting.plugin_redmine_gitlab_hook['fetch_updates'] == 'yes'
          git_success = update_repository(repository)
        end

        case request.params['object_kind']
          when 'push'
            process_push(request, repository)
          when 'merge_request'
            process_merge_request(request)
        end

        if git_success
          # Fetch the new changesets into Redmine
          repository.fetch_changesets
          render(:plain => 'OK', :status => :ok)
        else
          render(:plain => "Git command failed on repository: #{repository.identifier}!", :status => :not_acceptable)
        end
      end
    else
      raise ActionController::RoutingError.new('Not Found')
    end
  end


  private


  def system(command)
    Kernel.system(command)
  end


  # Executes shell command. Returns true if the shell command exits with a success status code
  def exec(command)
    logger.debug { "GitLabHook: Executing command: '#{command}'" }

    # Get a path to a temp file
    logfile = Tempfile.new('gitlab_hook_exec')
    logfile.close

    success = system("#{command} > #{logfile.path} 2>&1")
    output_from_command = File.readlines(logfile.path)
    if success
      logger.debug { "GitLabHook: Command output: #{output_from_command.inspect}"}
    else
      logger.error { "GitLabHook: Command '#{command}' didn't exit properly. Full output: #{output_from_command.inspect}"}
    end

    return success
  ensure
    logfile.unlink
  end

  # Executes shell command. Returns stdout
  def exec2(command)
    logger.debug { "GitLabHook: Executing command: '#{command}'" }

    # Get a path to a temp file
    logfile = Tempfile.new('gitlab_hook_exec')
    logfile.close

    success = system("#{command} > #{logfile.path} 2>&1")
    output_from_command = File.readlines(logfile.path)
    if success
      logger.info { "GitLabHook: Command output: #{output_from_command.inspect}"}
      return output_from_command[0].strip!
    else
      logger.error { "GitLabHook: Command '#{command}' didn't exit properly. Full output: #{output_from_command.inspect}"}
      return nil
    end
  ensure
    logfile.unlink
  end

  def git_command(prefix, command, repository)
    "#{prefix} " + GIT_BIN + " --git-dir=\"#{repository.url}\" #{command}"
  end


  def clone_repository(prefix, remote_url, local_url)
    "#{prefix} " + GIT_BIN + " clone --mirror #{remote_url} #{local_url}"
  end


  # Fetches updates from the remote repository
  def update_repository(repository)
    sleep(1) # https://redmine.imasdetres.com/issues/37850#note-10

    Setting.plugin_redmine_gitlab_hook['prune'] == 'yes' ? prune = ' -p' : prune = ''
    prefix = Setting.plugin_redmine_gitlab_hook['git_command_prefix'].to_s

    if Setting.plugin_redmine_gitlab_hook['all_branches'] == 'yes'
      command = git_command(prefix, "fetch --all#{prune}", repository)
      exec(command)
    else
      command = git_command(prefix, "fetch#{prune} origin", repository)
      if exec(command)
        command = git_command(prefix, "fetch#{prune} origin '+refs/heads/*:refs/heads/*'", repository)
        exec(command)
      end
    end
  end


  def get_repository_name
    return params[:repository_name] && params[:repository_name].downcase
  end


  def get_repository_namespace
    return params[:repository_namespace] && params[:repository_namespace].downcase
  end


  # Gets the repository identifier from the querystring parameters and if that's not supplied, assume
  # the GitLab project identifier is the same as the repository identifier.
  def get_repository_identifier
    repo_namespace = get_repository_namespace
    repo_name = get_repository_name || get_project_identifier
    identifier = repo_namespace.present? ? "#{repo_namespace}_#{repo_name}" : repo_name
    return identifier
  end

  # Gets the project identifier from the querystring parameters and if that's not supplied, assume
  # the GitLab repository identifier is the same as the project identifier.
  def get_project_identifier
    identifier = params[:project_id] || params[:repository_name]
    raise ActiveRecord::RecordNotFound, 'Project identifier not specified' if identifier.nil?
    return identifier
  end


  # Finds the Redmine project in the database based on the given project identifier
  def find_project
    identifier = get_project_identifier
    project = Project.find_by_identifier(identifier.downcase)
    raise ActiveRecord::RecordNotFound, "No project found with identifier '#{identifier}'" if project.nil?
    return project
  end


  # Returns the Redmine Repository object we are trying to update
  def find_repository
    project = find_project
    repository_id = get_repository_identifier
    repository = project.repositories.find_by_identifier_param(repository_id)

    if repository.nil?
      if Setting.plugin_redmine_gitlab_hook['auto_create'] == 'yes'
        repository = create_repository(project)
      else
        raise TypeError, "Project '#{project.to_s}' ('#{project.identifier}') has no repository or repository not found with identifier '#{repository_id}'"
      end
    else
      unless repository.is_a?(Repository::Git)
        raise TypeError, "'#{repository_id}' is not a Git repository"
      end
    end

    return repository
  end


  def create_repository(project)
    logger.debug('Trying to create repository...')
    raise TypeError, 'Local repository path is not set' unless Setting.plugin_redmine_gitlab_hook['local_repositories_path'].to_s.present?

    identifier = get_repository_identifier
    remote_url = params[:repository_git_url]
    prefix = Setting.plugin_redmine_gitlab_hook['git_command_prefix'].to_s

    raise TypeError, 'Remote repository URL is null' unless remote_url.present?

    local_root_path = Setting.plugin_redmine_gitlab_hook['local_repositories_path']
    repo_namespace = get_repository_namespace
    repo_name = get_repository_name
    local_url = File.join(local_root_path, repo_namespace, repo_name)
    git_file = File.join(local_url, 'HEAD')

    unless File.exists?(git_file)
      FileUtils.mkdir_p(local_url)
      command = clone_repository(prefix, remote_url, local_url)
      unless exec(command)
        raise RuntimeError, "Can't clone URL #{remote_url}"
      end
    end
    repository = Repository::Git.new
    repository.identifier = identifier
    repository.url = local_url
    repository.is_default = true
    repository.project = project
    repository.save
    return repository
  end

  def process_push(request, repository)
    logger.info("GitLabHook: Processing push")

    if request.params['before'] == '0000000000000000000000000000000000000000'
      request.params['ref'].scan(%r{[#/](?<issue_id>[0-9]+)}) do
        issue = Issue.find_by(:id => $~['issue_id'])

        user = User.find_by_login(request.params['user_username'])
        user ||= User.anonymous

        branch = request.params['ref'].gsub!('refs/heads/', '')
        branch_url = "#{request.params['project']['web_url']}/compare/#{request.params['project']['default_branch']}...#{branch}"

        logger.info("GitLabHook: Commenting on issue #{issue.id} as #{user.login}")
        journal = issue.init_journal(user)
        journal.notes = 'p{ border:1px black; border-radius:1em; padding:1em; background:#EEEEEE; }. '
        journal.notes += "Creada *nueva rama* \"#{branch}\":#{branch_url} de *#{request.params['project']['name']}*"

        unless issue.save
          logger.warn("GitLabHook: Issue ##{issue.id} could not be saved")
        end
      end
    end

    for commit in request.params['commits'] do
      #commit['message'].scan(%r{[#/](?<issue_id>[0-9]+)}) do
      #  issue_id = $~['issue_id']
      commit['message'].scan(%r{[#/](?<issue_id>[0-9]+)[\W_]}).uniq.each do |issue_id|
        # app/models/mail_handler.rb
        logger.info("GitLabHook: WHAT THE FUCK #{issue_id}")
        issue = Issue.find_by(:id => issue_id)
        unless issue
          logger.warn("Could not find issue ##{issue_id}")
          next
        end

        user = User.find_by_mail(commit['author']['email'])
        user ||= User.anonymous

        prefix = Setting.plugin_redmine_gitlab_hook['git_command_prefix'].to_s

        version = exec2(git_command(prefix, "describe --long #{commit['id']}", repository))
        version ||= commit['id']
        branch = exec2(git_command(prefix, "branch --contains #{commit['id']}", repository))
        branch = branch ? branch.gsub(/^\* /, '') : '??'

        if branch != request.params['project']['default_branch'] && branch !~ %r{/#{issue.id}}
          logger.info("GitLabHook: Ignoring commit #{commit['id']} because branch (#{branch}) is not the default branch (#{request.params['project']['default_branch']}) and is not related to issue #{issue.id}")
          next
        end
        #if branch != request.params['project']['default_branch']
        #  logger.info("GitLabHook: Ignoring commit #{commit['id']} because branch (#{branch}) is not the default branch (#{request.params['project']['default_branch']})")
        #  next
        #end
        if commit['message'] =~ /Merge branch '#{request.params['project']['default_branch']}' into/
          logger.info("GitLabHook: Ignoring commit #{commit['id']} with message \"#{commit['message']}\"")
	  next
        end

        message = commit['message'].dup
        message.gsub!(/\[([a-z]+ )?#[0-9]+\]/, '')
        message.gsub!(/^Merge branch .* into .*/, '')
        message.gsub!(/^See merge request .*/, '') # TODO: id3/4access!677 --> https://git.imasdetres.com/id3/4access/merge_requests/677
        message.gsub!(/^$\n/, '')
        message.strip!

        logger.info("GitLabHook: Commenting on issue #{issue.id} as #{user.login}")
        journal = issue.init_journal(user)
        journal.notes = 'p{ border:1px black; border-radius:1em; padding:1em; background:#EEEEEE; }. '
        journal.notes += "Creada *nueva versión* \"#{version}\":#{commit['url']} de *#{request.params['project']['name']}* (rama *#{branch}*)"

        unless message.empty?
          journal.notes += "\n*Descripción*: _{font-size:1.2em}#{message}_"
        end

        subnotes = ''
        if commit['message'] =~ /\[closes #[0-9]+\]/
          subnotes += "\nEsta versión de $project resuelve esta tarea, pero necesita pasar *pruebas en QA* antes de ser instalada en cliente."
          #subnotes += '\nEsta versión de $project resuelve esta tarea.'
        end

        if request.params['project']['name'] == "4access"
          subnotes += "\n[[ambrosio:Uso_de_Ambrosio|Instrucciones para compilar esta versión de 4access]]"
          subnotes += ' ("Acceso directo a Ambrosio/4Access":https://ambrosio.imasdetres.com/job/4Access%20(autobuild)/build)'
        end

        unless subnotes.empty?
          journal.notes += "\n\np{ font-size:0.9em; text-align:right; }. #{subnotes}"
        end

        unless issue.save
          logger.warn("Issue ##{issue.id} could not be saved")
        end
      end
    end
  end

  def process_merge_request(request)
    logger.info("GitLabHook: Processing MR")

    source_branch = request.params['object_attributes']['source_branch']
    if source_branch =~ %r{[^/]*/(?<issue_id>[0-9]+)}
      # app/models/mail_handler.rb
      issue = Issue.find_by(:id => $~['issue_id'])

      user = User.find_by_login(request.params['user']['username'])
      user ||= User.anonymous

      state_id_map = {
        1 => 'opened',
        2 => 'closed',
        3 => 'merged',
        4 => 'locked'
      }
      state_tr_map = {
        'created' => 'creado',
        'opened' => 'abierto',
        'closed' => 'cerrado',
        'merged' => 'mugido',
        'locked' => 'bloqueado'
      }
      verb_icon_map = {
        'closed' => '❌',
        'merged' => '✅🎉'
      }

      verb = nil
      verb = request.params['changes'].empty? ? 'created' : verb
      verb = request.params['changes'].key?('created_at') ? 'created' : verb
      verb = request.params['changes'].key?('state') ? request.params['changes']['state']['current'] : verb
      verb = request.params['changes'].key?('state_id') ? state_id_map[request.params['changes']['state_id']['current']] : verb
      if verb
        logger.info("GitLabHook: Commenting on issue #{issue.id} as #{user.login}")
        journal = issue.init_journal(user)
        journal.notes = "p{ border:1px black; border-radius:1em; padding:1em; background:#EEEEEE; }. "
        journal.notes += "#{state_tr_map[verb].capitalize()} \"MR##{request.params['object_attributes']['iid']}\":#{request.params['object_attributes']['url']}"
        journal.notes += " (@#{request.params['object_attributes']['source_branch']}@"
        journal.notes += " ➔ @#{request.params['object_attributes']['target_branch']}@)"
        journal.notes += verb_icon_map.key?(verb) ? " #{verb_icon_map[verb]}" : ""
        unless issue.save
          logger.warn("GitLabHook: Issue ##{issue.id} could not be saved")
        end
      else
        logger.info("GitLabHook: No state change detected")
      end
    else
      logger.warn("GitLabHook: Could not find issue id on source branch #{source_branch}")
    end
  end

end
