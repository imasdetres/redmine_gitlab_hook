require 'minitest/autorun'
require_relative '../../lib/issue_id_extractor'

class IssueIdExtractorTest < Minitest::Test

  # =========================================================================
  # from_commit_message – should match
  # =========================================================================

  def test_bracket_ref_simple
    assert_includes IssueIdExtractor.from_commit_message("Fix layout [#1234]"), 1234
  end

  def test_bracket_ref_with_verb
    assert_includes IssueIdExtractor.from_commit_message("Done [closes #5678]"), 5678
  end

  def test_bracket_ref_refs
    assert_includes IssueIdExtractor.from_commit_message("WIP [refs #42]"), 42
  end

  def test_standalone_hash_4_digits
    assert_includes IssueIdExtractor.from_commit_message("Relates to #9999"), 9999
  end

  def test_standalone_hash_5_digits
    assert_includes IssueIdExtractor.from_commit_message("See #12345"), 12345
  end

  def test_standalone_hash_6_digits
    assert_includes IssueIdExtractor.from_commit_message("See #156056"), 156056
  end

  def test_multiple_bracket_refs
    ids = IssueIdExtractor.from_commit_message("[#100] and [#200]")
    assert_includes ids, 100
    assert_includes ids, 200
  end

  def test_mixed_bracket_and_standalone
    ids = IssueIdExtractor.from_commit_message("[#100] relates to #2000")
    assert_includes ids, 100
    assert_includes ids, 2000
  end

  def test_hash_after_newline
    ids = IssueIdExtractor.from_commit_message("Title [#100]\n\nAlso fixes #2000")
    assert_includes ids, 100
    assert_includes ids, 2000
  end

  def test_deduplication
    ids = IssueIdExtractor.from_commit_message("[#1000] #1000")
    assert_equal [1000], ids
  end

  # =========================================================================
  # from_commit_message – standalone #N with < 4 digits should NOT match
  # =========================================================================

  def test_no_match_standalone_hash_1_digit
    ids = IssueIdExtractor.from_commit_message("Relates to #7")
    assert_empty ids, "Standalone #7 (1 digit) should not match — use [#7] instead"
  end

  def test_no_match_standalone_hash_2_digits
    ids = IssueIdExtractor.from_commit_message("Relates to #42")
    assert_empty ids, "Standalone #42 (2 digits) should not match — use [#42] instead"
  end

  def test_no_match_standalone_hash_3_digits
    ids = IssueIdExtractor.from_commit_message("Relates to #999")
    assert_empty ids, "Standalone #999 (3 digits) should not match — use [#999] instead"
  end

  # =========================================================================
  # from_commit_message – bracketed [#N] with < 4 digits SHOULD still match
  # =========================================================================

  def test_bracket_ref_1_digit
    assert_includes IssueIdExtractor.from_commit_message("[#7]"), 7
  end

  def test_bracket_ref_2_digits
    assert_includes IssueIdExtractor.from_commit_message("[#42]"), 42
  end

  def test_bracket_ref_3_digits
    assert_includes IssueIdExtractor.from_commit_message("[#100]"), 100
  end

  # =========================================================================
  # from_commit_message – should NOT match (false positives)
  # =========================================================================

  def test_no_match_slash_number_in_text
    # "0570/0571/0572/0573" — these are migration numbers, not issue refs
    ids = IssueIdExtractor.from_commit_message(
      "renumerar migracion 0570 -> 0574\n0570/0571/0572/0573 de develop"
    )
    assert_empty ids, "Should not match /0571 or /0573 as issue IDs"
  end

  def test_no_match_test_results_fraction
    # "CecaProvider 7/7" — test result fractions
    ids = IssueIdExtractor.from_commit_message(
      "TransbankProvider 13/13, CecaProvider 7/7, ApplyInstanceParametersCeca 4/4"
    )
    assert_empty ids, "Should not match 7/7 or 4/4 as issue IDs"
  end

  def test_no_match_path_component
    # "id3/4access!677" is a GitLab MR reference, not a Redmine issue
    ids = IssueIdExtractor.from_commit_message("See merge request id3/4access!677")
    assert_empty ids, "Should not match path components as issue IDs"
  end

  def test_no_match_version_slash
    # "v2/something" is not an issue ref
    ids = IssueIdExtractor.from_commit_message("Updated api/v2/endpoint")
    assert_empty ids, "Should not match api/v2 as issue ID"
  end

  def test_no_match_html_entity
    ids = IssueIdExtractor.from_commit_message("Character &#123; in template")
    assert_empty ids, "Should not match HTML entities like &#123;"
  end

  def test_no_match_plain_number
    # A plain number without # should not match
    ids = IssueIdExtractor.from_commit_message("Fixed bug in line 573")
    assert_empty ids, "Should not match plain numbers"
  end

  # =========================================================================
  # from_branch_ref – should match
  # =========================================================================

  def test_feature_branch_ref
    ids = IssueIdExtractor.from_branch_ref("refs/heads/feature/1234_my_feature")
    assert_includes ids, 1234
  end

  def test_fix_branch_ref
    ids = IssueIdExtractor.from_branch_ref("refs/heads/fix/5678_fix_thing")
    assert_includes ids, 5678
  end

  def test_bugfix_branch_ref
    ids = IssueIdExtractor.from_branch_ref("refs/heads/bugfix/42_urgent")
    assert_includes ids, 42
  end

  def test_hotfix_branch_ref
    ids = IssueIdExtractor.from_branch_ref("refs/heads/hotfix/999_critical")
    assert_includes ids, 999
  end

  def test_feature_branch_with_hyphen_separator
    ids = IssueIdExtractor.from_branch_ref("refs/heads/feature/1234-my-feature")
    assert_includes ids, 1234
  end

  def test_plain_branch_name
    ids = IssueIdExtractor.from_branch_ref("feature/1234_desc")
    assert_includes ids, 1234
  end

  # =========================================================================
  # from_branch_ref – should NOT match
  # =========================================================================

  def test_no_match_random_slash_number
    # "release/2.0" should NOT match issue #2
    ids = IssueIdExtractor.from_branch_ref("refs/heads/release/2.0")
    assert_empty ids, "Should not match release/2.0 as issue ID"
  end

  def test_no_match_version_branch
    ids = IssueIdExtractor.from_branch_ref("refs/heads/release/571")
    assert_empty ids, "Should not match release/571 — 'release' is not a known prefix"
  end

  def test_no_match_develop
    ids = IssueIdExtractor.from_branch_ref("refs/heads/develop")
    assert_empty ids
  end

  def test_no_match_master
    ids = IssueIdExtractor.from_branch_ref("refs/heads/master")
    assert_empty ids
  end

  def test_no_match_arbitrary_prefix
    ids = IssueIdExtractor.from_branch_ref("refs/heads/user/573_experiment")
    assert_empty ids, "Should not match user/573 — 'user' is not a known prefix"
  end

  # =========================================================================
  # from_mr_source_branch
  # =========================================================================

  def test_mr_feature_branch
    assert_equal 1234, IssueIdExtractor.from_mr_source_branch("feature/1234_desc")
  end

  def test_mr_fix_branch
    assert_equal 5678, IssueIdExtractor.from_mr_source_branch("fix/5678_desc")
  end

  def test_mr_bugfix_branch
    assert_equal 42, IssueIdExtractor.from_mr_source_branch("bugfix/42_desc")
  end

  def test_mr_no_match_random_prefix
    assert_nil IssueIdExtractor.from_mr_source_branch("release/2.0")
  end

  def test_mr_no_match_no_separator
    # "feature/1234" without trailing _ or - should still match (end-of-string)
    assert_equal 1234, IssueIdExtractor.from_mr_source_branch("feature/1234")
  end

  # =========================================================================
  # branch_related_to_issue?
  # =========================================================================

  def test_branch_related_feature
    assert IssueIdExtractor.branch_related_to_issue?("feature/1234_desc", 1234)
  end

  def test_branch_not_related_wrong_prefix
    refute IssueIdExtractor.branch_related_to_issue?("release/1234", 1234)
  end

  def test_branch_not_related_wrong_id
    refute IssueIdExtractor.branch_related_to_issue?("feature/1234_desc", 5678)
  end

  def test_branch_related_accepts_string_id
    assert IssueIdExtractor.branch_related_to_issue?("feature/1234_desc", "1234")
  end

  # =========================================================================
  # Real-world false-positive scenarios from Redmine
  # =========================================================================

  def test_real_world_issue_7_false_positive
    # Commit message contained "CecaProvider 7/7" — was falsely associated to issue #7
    message = <<~MSG
      test(tpvs): eliminar 9 tests obsoletos por refactor TPV cluster v3 [#156056]

      Run de las 3 clases afectadas tras eliminar: 24/24 OK
      (TransbankProvider 13/13, CecaProvider 7/7, ApplyInstanceParametersCeca
      4/4).
    MSG
    ids = IssueIdExtractor.from_commit_message(message)
    assert_includes ids, 156056, "Should match the actual issue reference [#156056]"
    refute_includes ids, 7,  "Should NOT match 7/7 as issue #7"
    refute_includes ids, 13, "Should NOT match 13/13 as issue #13"
    refute_includes ids, 4,  "Should NOT match 4/4 as issue #4"
    refute_includes ids, 24, "Should NOT match 24/24 as issue #24"
  end

  def test_real_world_issue_571_573_false_positive
    # Commit mentioned "0570/0571/0572/0573" — falsely associated to issues #571 and #573
    message = <<~MSG
      fix(database): renumerar migracion discount_coupon 0570 -> 0574 [#156056]

      La migracion del cluster #156056 (discount_coupon + global_discount
      invoice item types 16/17) renumerada a 0574 (siguiente libre tras
      0570/0571/0572/0573 de develop).

      Quinta renumeracion del cluster por sucesivos conflicts con develop:
      0560 -> 0564 -> 0566 -> 0567 -> 0568 -> 0570 -> 0574.
    MSG
    ids = IssueIdExtractor.from_commit_message(message)
    assert_includes ids, 156056, "Should match the actual issue reference [#156056]"
    refute_includes ids, 571, "Should NOT match /0571 as issue #571"
    refute_includes ids, 572, "Should NOT match /0572 as issue #572"
    refute_includes ids, 573, "Should NOT match /0573 as issue #573"
    refute_includes ids, 570, "Should NOT match /0570 as issue #570"
  end

  def test_real_world_merge_commit_with_branch_ref
    # A merge commit message like "Merge branch 'feature/1234_desc' into develop"
    # should still pick up the issue from the branch ref in the message
    message = "Merge branch 'feature/1234_desc' into develop"
    ids = IssueIdExtractor.from_commit_message(message)
    # This is a merge commit message — the issue should be found via branch processing,
    # not via commit message scanning. No #1234 in the message.
    assert_empty ids, "Merge commit messages without #N should not yield issue IDs"
  end
end
