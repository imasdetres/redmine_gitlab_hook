# Extracts Redmine issue IDs from commit messages, branch refs, and MR source
# branches using strict patterns to avoid false associations.
#
# Valid patterns:
#   - Commit messages: [#1234], [closes #1234], [refs #1234] (any digit count)
#                      #1234 standalone (minimum 4 digits to avoid false positives)
#   - Branch refs/names: feature/1234_desc, fix/1234_desc, bugfix/1234_desc
#   - MR source branches: feature/1234_desc, fix/1234_desc, bugfix/1234_desc
module IssueIdExtractor

  # Known branch prefixes that carry a Redmine issue ID.
  BRANCH_PREFIXES = %w[feature fix bugfix hotfix].freeze
  BRANCH_PREFIX_RE = Regexp.union(BRANCH_PREFIXES).freeze

  # Matches [#1234], [closes #1234], [refs #1234], etc.
  BRACKET_REF_RE = /\[(?:[a-z]+ )?#(\d+)\]/

  # Matches a standalone #1234 (4+ digits) that is NOT inside brackets (we
  # handle brackets separately).  Preceded by start-of-string or whitespace,
  # followed by end-of-string, whitespace or punctuation — but NOT preceded
  # by & (HTML entities like &#1234;) or / (path components like foo/1234).
  # Short IDs (#1, #12, #123) are too ambiguous without brackets and are
  # rejected; use [#123] for those.
  HASH_REF_RE = /(?<![&\/])#(\d{4,})(?=[\s,;:)\].]|$)/

  # Matches branch names like feature/1234_description or fix/1234-description.
  # The issue ID must be followed by a separator (_ or -) or end-of-string.
  BRANCH_ISSUE_RE = /\b(?:#{BRANCH_PREFIX_RE})\/(\d+)(?:[_\-]|$)/

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  # Extract issue IDs from a commit message.
  # Returns a unique array of integer IDs.
  def self.from_commit_message(message)
    ids = []
    message.scan(BRACKET_REF_RE)  { |m| ids << m[0].to_i }
    message.scan(HASH_REF_RE)     { |m| ids << m[0].to_i }
    ids.uniq
  end

  # Extract issue IDs from a branch ref (e.g. "refs/heads/feature/1234_desc")
  # or a plain branch name (e.g. "feature/1234_desc").
  # Returns a unique array of integer IDs.
  def self.from_branch_ref(ref)
    ids = []
    ref.scan(BRANCH_ISSUE_RE) { |m| ids << m[0].to_i }
    ids.uniq
  end

  # Extract the issue ID from an MR source branch name.
  # Returns a single integer ID or nil.
  def self.from_mr_source_branch(branch)
    if branch =~ BRANCH_ISSUE_RE
      $1.to_i
    end
  end

  # Check whether a branch name is related to a specific issue ID.
  # Uses the same strict pattern as from_branch_ref.
  def self.branch_related_to_issue?(branch, issue_id)
    from_branch_ref(branch).include?(issue_id.to_i)
  end
end
