# Interprets GitLab merge_request webhook payloads to decide which "verb"
# (event type) a delivery represents, or nil when the delivery should not
# produce an issue note.
#
# Background (see #177020):
#   GitLab fires the merge_request hook on every MR mutation. The top-level
#   `object_attributes.action` field is the authoritative event type
#   (open/reopen/close/merge/update/approved/...). The `changes` hash only
#   describes which attributes mutated in *this* delivery and is NOT a reliable
#   signal for the event type: an "open" delivery may carry only
#   `merge_status`/`prepared_at`/`updated_at` (no `created_at`/`state`/`state_id`),
#   and an "update" delivery may carry an empty `changes` hash. The old
#   `changes`-only heuristic therefore both dropped legitimate open events and
#   misfired "created" on plain updates.
#
#   So we drive the verb from `action` first, and only fall back to the
#   `changes`-based heuristics for older payloads that lack `action`.
module MrEvent

  # GitLab MR `action` -> internal verb. Actions not listed (e.g. 'update',
  # 'approved', 'unapproved', 'approval', 'unapproval') map to nil = no note.
  ACTION_VERB_MAP = {
    'open'   => 'created',
    'reopen' => 'reopened',
    'close'  => 'closed',
    'merge'  => 'merged'
  }.freeze

  # GitLab MR `state_id` -> internal verb (fallback path only).
  STATE_ID_MAP = {
    1 => 'opened',
    2 => 'closed',
    3 => 'merged',
    4 => 'locked'
  }.freeze

  # Returns the verb for a merge_request webhook payload, or nil if the event
  # should not create a note.
  #
  # @param params [Hash] the parsed webhook params (string keys), i.e.
  #   request.params for the merge_request hook.
  def self.verb(params)
    return nil if params.nil?
    object_attributes = params['object_attributes'] || {}

    action = object_attributes['action']
    return ACTION_VERB_MAP[action] if action

    # Fallback for legacy payloads without a top-level `action`.
    changes = params['changes'] || {}
    verb = nil
    verb = changes.empty? ? 'created' : verb
    verb = changes.key?('created_at') ? 'created' : verb
    verb = changes.key?('state') ? changes['state']['current'] : verb
    verb = changes.key?('state_id') ? STATE_ID_MAP[changes['state_id']['current']] : verb
    verb
  end

end
