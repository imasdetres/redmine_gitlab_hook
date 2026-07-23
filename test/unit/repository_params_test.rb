require 'minitest/autorun'
require_relative '../../lib/repository_params'

# Tests for #37852: the gitlab_hook URL should only need key/project_id; the
# repository namespace, name and git URL are derived from the GitLab webhook
# payload's `project` object when absent from the query string.
#
# The payload subset below matches what GitLab actually sends (verified via
# requestbin in the issue description, and against git.imasdetres.com): note
# that `name`/`namespace` are DISPLAY names ("iD3"), while
# `path_with_namespace` is the real path ("id3/ChibiATM").
class RepositoryParamsTest < Minitest::Test

  PAYLOAD_PROJECT = {
    'name' => 'ChibiATM',
    'namespace' => 'iD3',
    'path_with_namespace' => 'id3/ChibiATM',
    'git_ssh_url' => 'git@git.imasdetres.com:id3/ChibiATM.git',
    'git_http_url' => 'https://git.imasdetres.com/id3/ChibiATM.git',
    'web_url' => 'https://git.imasdetres.com/id3/ChibiATM',
    'default_branch' => 'master'
  }.freeze

  # Simulates controller params for a hook configured the NEW way:
  # only ?project_id= in the query string, everything else from the payload.
  def payload_only_params
    { 'project_id' => '4access', 'project' => PAYLOAD_PROJECT.dup }
  end

  # Simulates a LEGACY hook URL carrying all query-string params
  # (e.g. the existing id3/4access hook).
  def legacy_params
    {
      'project_id' => '4access',
      'repository_namespace' => 'id3',
      'repository_name' => '4access',
      'repository_git_url' => 'git@git.imasdetres.com:id3/4access.git',
      'project' => PAYLOAD_PROJECT.dup
    }
  end

  # ---- derivation from payload --------------------------------------------

  def test_name_derived_from_path_with_namespace
    assert_equal 'chibiatm', RepositoryParams.name(payload_only_params)
  end

  def test_namespace_derived_from_path_with_namespace
    assert_equal 'id3', RepositoryParams.namespace(payload_only_params)
  end

  def test_namespace_is_not_the_display_name
    # "iD3" is the namespace display name; the path is "id3". Downcased they
    # coincide for id3, so assert on a case where they truly differ.
    params = payload_only_params
    params['project']['namespace'] = 'My Fancy Group'
    params['project']['path_with_namespace'] = 'my-fancy-group/repo'
    assert_equal 'my-fancy-group', RepositoryParams.namespace(params)
    assert_equal 'repo', RepositoryParams.name(params)
  end

  def test_git_url_derived_from_git_ssh_url
    assert_equal 'git@git.imasdetres.com:id3/ChibiATM.git',
                 RepositoryParams.git_url(payload_only_params)
  end

  def test_nested_group_namespace_keeps_full_path
    params = payload_only_params
    params['project']['path_with_namespace'] = 'group/subgroup/repo'
    assert_equal 'group/subgroup', RepositoryParams.namespace(params)
    assert_equal 'repo', RepositoryParams.name(params)
  end

  # ---- query-string precedence (legacy hooks unaffected) ------------------

  def test_query_string_name_takes_precedence
    assert_equal '4access', RepositoryParams.name(legacy_params)
  end

  def test_query_string_namespace_takes_precedence
    assert_equal 'id3', RepositoryParams.namespace(legacy_params)
  end

  def test_query_string_git_url_takes_precedence
    assert_equal 'git@git.imasdetres.com:id3/4access.git',
                 RepositoryParams.git_url(legacy_params)
  end

  def test_query_string_values_are_downcased
    params = { 'repository_namespace' => 'iD3', 'repository_name' => 'ChibiATM' }
    assert_equal 'id3', RepositoryParams.namespace(params)
    assert_equal 'chibiatm', RepositoryParams.name(params)
  end

  # ---- absent data ----------------------------------------------------------

  def test_all_nil_without_payload_or_query_params
    params = { 'project_id' => '4access' }
    assert_nil RepositoryParams.name(params)
    assert_nil RepositoryParams.namespace(params)
    assert_nil RepositoryParams.git_url(params)
  end

  def test_empty_strings_treated_as_absent
    params = {
      'repository_name' => '', 'repository_namespace' => '',
      'repository_git_url' => '', 'project' => PAYLOAD_PROJECT.dup
    }
    assert_equal 'chibiatm', RepositoryParams.name(params)
    assert_equal 'id3', RepositoryParams.namespace(params)
    assert_equal 'git@git.imasdetres.com:id3/ChibiATM.git', RepositoryParams.git_url(params)
  end

  def test_project_without_path_with_namespace
    params = { 'project' => { 'name' => 'x' } }
    assert_nil RepositoryParams.name(params)
    assert_nil RepositoryParams.namespace(params)
  end

end
