# Derives repository parameters for the gitlab_hook endpoint [#37852].
#
# Historically the webhook URL had to carry repository_namespace,
# repository_name and repository_git_url as query-string parameters. All of
# that information is already present in the GitLab webhook JSON payload
# (both push and merge_request events carry a top-level `project` object), so
# these helpers fall back to the payload when a query param is absent.
# Query-string parameters keep precedence: existing hooks are unaffected.
#
# Derivation uses `project.path_with_namespace` (e.g. "id3/ChibiATM"), NOT
# `project.name`/`project.namespace`: those are display names (e.g. "iD3" for
# the "id3" group) and may contain spaces or arbitrary capitalization.
# `project.git_ssh_url` maps to repository_git_url.
module RepositoryParams

  # @param params [Hash, ActionController::Parameters] webhook params with
  #   string keys (query string + parsed JSON payload merged, i.e. the
  #   controller's `params`).
  # @return [String, nil] the repository name (downcased), or nil.
  def self.name(params)
    name = presence(params['repository_name']) || path_parts(params)[1]
    name && name.downcase
  end

  # @return [String, nil] the repository namespace (downcased), or nil.
  def self.namespace(params)
    namespace = presence(params['repository_namespace']) || path_parts(params)[0]
    namespace && namespace.downcase
  end

  # @return [String, nil] the remote git URL used to clone the repository.
  def self.git_url(params)
    presence(params['repository_git_url']) || params.dig('project', 'git_ssh_url')
  end

  # Splits the payload's project.path_with_namespace into [namespace, name].
  # Nested groups keep their full path as namespace ("group/subgroup").
  # @return [Array(String, nil)] [namespace, name], each possibly nil.
  def self.path_parts(params)
    path = presence(params.dig('project', 'path_with_namespace'))
    return [nil, nil] unless path
    parts = path.split('/')
    [presence(parts[0..-2].join('/')), parts.last]
  end

  # String#presence without depending on ActiveSupport (these units are also
  # exercised by standalone minitest).
  def self.presence(value)
    value.nil? || value.empty? ? nil : value
  end
  private_class_method :presence

end
