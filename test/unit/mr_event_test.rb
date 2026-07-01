require 'minitest/autorun'
require_relative '../../lib/mr_event'

# Regression tests for #177020: a merge_request "open" webhook whose `changes`
# hash carried only merge-status metadata (merge_status/updated_at/prepared_at)
# produced no issue note, because the verb was derived solely from `changes`.
#
# All payloads below are the field-subsets actually observed in production.log
# during the #177020 investigation (7 real MR webhooks across a 200k-line
# window). MrEvent.verb only reads `object_attributes.action`, `changes` keys,
# and (fallback) `changes.state`/`changes.state_id`.
class MrEventTest < Minitest::Test

  # ---- action-driven (current GitLab) -------------------------------------

  # The #177020 bug: open delivery whose `changes` lacks created_at/state/state_id.
  # Old code returned nil (no note); must now be 'created'.
  def test_open_with_merge_status_changes_is_created
    payload = {
      'object_attributes' => { 'action' => 'open', 'iid' => 2335 },
      'changes' => { 'merge_status' => {}, 'updated_at' => {}, 'prepared_at' => {} }
    }
    assert_equal 'created', MrEvent.verb(payload)
  end

  # An "update" delivery with an EMPTY changes hash used to misfire 'created'
  # (false-positive note). It must now produce no note.
  def test_update_with_empty_changes_is_nil
    payload = {
      'object_attributes' => { 'action' => 'update', 'iid' => 1863 },
      'changes' => {}
    }
    assert_nil MrEvent.verb(payload)
  end

  def test_merge_action_is_merged
    payload = {
      'object_attributes' => { 'action' => 'merge', 'iid' => 2300 },
      'changes' => { 'merge_commit_sha' => {}, 'state_id' => { 'current' => 3 }, 'updated_at' => {} }
    }
    assert_equal 'merged', MrEvent.verb(payload)
  end

  def test_close_action_is_closed
    payload = { 'object_attributes' => { 'action' => 'close', 'iid' => 1 }, 'changes' => {} }
    assert_equal 'closed', MrEvent.verb(payload)
  end

  # reopen gets its own verb so it is NOT deduplicated against the creation note.
  def test_reopen_action_is_reopened
    payload = { 'object_attributes' => { 'action' => 'reopen', 'iid' => 1 }, 'changes' => {} }
    assert_equal 'reopened', MrEvent.verb(payload)
  end

  def test_approved_action_is_nil
    payload = { 'object_attributes' => { 'action' => 'approved', 'iid' => 1 }, 'changes' => {} }
    assert_nil MrEvent.verb(payload)
  end

  def test_unknown_action_is_nil
    payload = { 'object_attributes' => { 'action' => 'wibble', 'iid' => 1 }, 'changes' => {} }
    assert_nil MrEvent.verb(payload)
  end

  # ---- legacy fallback (payloads without a top-level `action`) -------------

  def test_fallback_empty_changes_is_created
    payload = { 'object_attributes' => { 'iid' => 1 }, 'changes' => {} }
    assert_equal 'created', MrEvent.verb(payload)
  end

  def test_fallback_created_at_is_created
    payload = { 'object_attributes' => { 'iid' => 1 }, 'changes' => { 'created_at' => {} } }
    assert_equal 'created', MrEvent.verb(payload)
  end

  def test_fallback_state_current_is_used
    payload = { 'object_attributes' => { 'iid' => 1 }, 'changes' => { 'state' => { 'current' => 'merged' } } }
    assert_equal 'merged', MrEvent.verb(payload)
  end

  def test_fallback_state_id_is_mapped
    payload = { 'object_attributes' => { 'iid' => 1 }, 'changes' => { 'state_id' => { 'current' => 3 } } }
    assert_equal 'merged', MrEvent.verb(payload)
  end

  # A legacy open-like delivery with only merge-status changes and no action
  # still yields nil (the pre-existing fallback limitation); such payloads no
  # longer occur from GitLab, which always sends `action`.
  def test_fallback_merge_status_only_is_nil
    payload = { 'object_attributes' => { 'iid' => 1 }, 'changes' => { 'merge_status' => {} } }
    assert_nil MrEvent.verb(payload)
  end

  # ---- robustness ---------------------------------------------------------

  def test_nil_params_is_nil
    assert_nil MrEvent.verb(nil)
  end

  def test_missing_object_attributes_falls_back
    assert_equal 'created', MrEvent.verb({ 'changes' => {} })
  end

end
