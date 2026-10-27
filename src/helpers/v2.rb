# Android calls the v2 REST paths while its websocket is still v1, so a v1 run also takes v2-encoded
# requests and answers them from v1-shaped data. These convert between the two encodings at that boundary.

# Moves every nested `custom` object back to its owner's root, the v1 request shape.
def flatten_custom(value)
  case value
  when Array
    value.map { |child| flatten_custom(child) }
  when Hash
    flat = value.transform_values { |child| flatten_custom(child) }
    custom = flat['custom']
    custom.kind_of?(Hash) ? custom.merge(flat.except('custom')) : flat
  else
    value
  end
end

# The fields each v2 response object declares (from the generated client models); v2 sends any
# other field under `custom`.
V2_DECLARED_KEYS = {
  channel: %w[
    cid created_at disabled frozen id type updated_at custom auto_translation_enabled auto_translation_language
    blocked cooldown deleted_at hidden hide_messages_before last_message_at member_count message_count
    mute_expires_at muted team truncated_at filter_tags members own_capabilities config created_by truncated_by
  ],
  user: %w[
    banned created_at id language online role updated_at blocked_user_ids teams custom avg_response_time
    deactivated_at deleted_at image last_active name revoke_tokens_issued_before teams_role invisible
    privacy_settings shadow_banned total_unread_count unread_channels unread_count unread_threads channel_mutes
    devices mutes ban_expires latest_hidden_channels
  ],
  member: %w[
    banned channel_role created_at notifications_muted shadow_banned updated_at custom archived_at ban_expires
    deleted_at invite_accepted_at invite_rejected_at invited is_moderator pinned_at role status user_id
    deleted_messages user
  ],
  message: %w[
    cid created_at deleted_reply_count html id mentioned_channel mentioned_here pinned reply_count shadowed silent
    text type updated_at attachments latest_reactions mentioned_users own_reactions restricted_visibility custom
    reaction_counts reaction_scores user command deleted_at deleted_for_me message_text_updated_at mml parent_id
    pin_expires pinned_at poll_id quoted_message_id show_in_channel mentioned_group_ids mentioned_groups
    mentioned_roles thread_participants draft i18n image_labels member mentioned_channel_members moderation pinned_by
    poll quoted_message reaction_groups reminder shared_location channel
  ],
  thread: %w[
    active_participant_count channel_cid created_at created_by_user_id parent_message_id participant_count
    reply_count title updated_at latest_replies custom deleted_at last_message_at read thread_participants channel
    created_by draft parent_message
  ],
  thread_participant: %w[
    channel_cid created_at last_read_at custom last_thread_message_at left_thread_at thread_id user_id user
  ],
  reaction: %w[
    created_at message_id score type updated_at user_id custom user
  ],
  poll: %w[
    allow_answers allow_user_suggested_options answers_count created_at created_by_id description enforce_unique_vote
    id name updated_at vote_count voting_visibility latest_answers options own_votes custom latest_votes_by_option
    vote_counts_by_option is_closed max_votes_allowed created_by
  ],
  poll_option: %w[
    id text custom
  ],
  attachment: %w[
    custom asset_url author_icon author_link author_name color fallback footer footer_icon image_url og_scrape_url
    original_height original_width pretext text thumb_url title title_link type actions fields giphy
  ],
  scheduled_message: %w[
    id cid user message scheduled_at status failure_reason created_at updated_at channel
  ],
  scheduled_message_content: %w[
    text custom html mentioned_channel mentioned_here mml parent_id pin_expires pinned poll_id quoted_message_id
    show_in_channel silent type attachments mentioned_group_ids mentioned_roles mentioned_users restricted_visibility
    shared_location
  ],
  scheduled_message_channel: %w[
    cid type id name image
  ]
}.freeze

# The object type each response key holds.
V2_CHILD_TYPES = {
  'channel' => :channel,
  'user' => :user, 'users' => :user, 'created_by' => :user, 'pinned_by' => :user, 'truncated_by' => :user,
  'mentioned_users' => :user, 'thread_participants' => :user, 'watchers' => :user, 'target' => :user,
  'banned_by' => :user, 'blocked_user' => :user,
  'member' => :member, 'members' => :member, 'membership' => :member,
  'message' => :message, 'messages' => :message, 'pinned_messages' => :message, 'quoted_message' => :message,
  'parent_message' => :message, 'latest_replies' => :message,
  'thread' => :thread, 'threads' => :thread,
  'reaction' => :reaction, 'reactions' => :reaction, 'latest_reactions' => :reaction, 'own_reactions' => :reaction,
  'poll' => :poll, 'poll_option' => :poll_option,
  'attachments' => :attachment,
  'scheduled_message' => :scheduled_message, 'scheduled_messages' => :scheduled_message
}.freeze

# Keys whose object type depends on the object holding them.
V2_NESTED_CHILD_TYPES = {
  [:poll, 'options'] => :poll_option,
  [:thread, 'thread_participants'] => :thread_participant,
  [:scheduled_message, 'message'] => :scheduled_message_content,
  [:scheduled_message, 'channel'] => :scheduled_message_channel
}.freeze

# Gives a v1-shaped response the v2 shape: every known object nests the fields its v2 model does not
# declare under `custom`, and carries `custom` even when it has none, as the API does.
def nest_v2_custom(value, type = nil)
  case value
  when Array
    value.map { |child| nest_v2_custom(child, type) }
  when Hash
    shaped = value.to_h do |key, child|
      child_type = V2_NESTED_CHILD_TYPES.fetch([type, key]) { V2_CHILD_TYPES[key] }
      [key, nest_v2_custom(child, child_type)]
    end
    type ? nest_undeclared(shaped, V2_DECLARED_KEYS[type]) : shaped
  else
    value
  end
end

def nest_undeclared(object, declared)
  undeclared = object.reject { |key, _| declared.include?(key) }
  custom = object['custom'].kind_of?(Hash) ? object['custom'] : {}
  object.slice(*declared).merge('custom' => custom.merge(undeclared))
end
