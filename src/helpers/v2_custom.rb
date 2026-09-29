# v2 nests the extra data of users, channels, members, messages and the like under `custom`,
# while the recorded fixtures and the server state keep the v1 shape with the extra data
# flattened next to the declared fields. `to_v2` rebuilds the v2 shape on the way out, so v1
# clients keep getting the flattened payloads untouched.
#
# `keys` lists the fields each OpenAPI response model declares; every other key moves into
# `custom`. A model without `keys` is a plain wrapper that only walks into its children.
# `children` maps a field to the model of its value, `map` applies a model to every value.

V2_USER_KEYS = %w[
  avg_response_time banned blocked_user_ids created_at deactivated_at deleted_at id image language last_active
  name online revoke_tokens_issued_before role teams teams_role updated_at
].freeze

V2_MESSAGE_KEYS = %w[
  attachments cid command created_at deleted_at deleted_for_me deleted_reply_count draft html i18n id image_labels
  latest_reactions member mentioned_channel mentioned_channel_members mentioned_group_ids mentioned_groups
  mentioned_here mentioned_roles mentioned_users message_text_updated_at mml moderation own_reactions parent_id
  pin_expires pinned pinned_at pinned_by poll poll_id quoted_message quoted_message_id reaction_counts
  reaction_groups reaction_scores reminder reply_count restricted_visibility shadowed shared_location
  show_in_channel silent text thread_participants type updated_at user
].freeze

V2_MESSAGE_CHILDREN = {
  'attachments' => :attachment,
  'draft' => :draft,
  'latest_reactions' => :reaction,
  'mentioned_users' => :user,
  'own_reactions' => :reaction,
  'pinned_by' => :user,
  'poll' => :poll,
  'quoted_message' => :message,
  'reminder' => :wrapper,
  'thread_participants' => :user,
  'user' => :user
}.freeze

V2_MODELS = {
  # Response roots, events, ChannelStateResponse, ReadStateResponse, ReminderResponseData,
  # PollVoteResponseData and the mute records.
  wrapper: {
    children: {
      'channel' => :channel,
      'channel_mutes' => :wrapper,
      'channels' => :wrapper,
      'created_by' => :user,
      'draft' => :draft,
      'event' => :wrapper,
      'events' => :wrapper,
      'latest_answers' => :wrapper,
      'me' => :own_user,
      'member' => :member,
      'members' => :member,
      'membership' => :member,
      'message' => :message,
      'messages' => :message,
      'mutes' => :wrapper,
      'own_votes' => :wrapper,
      'pinned_messages' => :message,
      'poll' => :poll,
      'poll_vote' => :wrapper,
      'reaction' => :reaction,
      'read' => :wrapper,
      'reminder' => :wrapper,
      'reminders' => :wrapper,
      'results' => :search_result,
      'target' => :user,
      'thread' => :thread,
      'thread_participants' => :user,
      'threads' => :thread,
      'user' => :user,
      'users' => :user,
      'vote' => :wrapper,
      'watchers' => :user
    }
  },
  # UserResponse
  user: { keys: V2_USER_KEYS, children: {} },
  # OwnUserResponse
  own_user: {
    keys: V2_USER_KEYS + %w[
      channel_mutes devices invisible latest_hidden_channels mutes privacy_settings push_preferences
      total_unread_count total_unread_count_by_team unread_channels unread_count unread_threads
    ],
    children: { 'channel_mutes' => :wrapper, 'mutes' => :wrapper }
  },
  # ChannelResponse. `name` and `image` are not declared, so they are custom data in v2.
  channel: {
    keys: %w[
      auto_translation_enabled auto_translation_language blocked cid config cooldown created_at created_by
      deleted_at disabled filter_tags frozen hidden hide_messages_before id last_message_at member_count members
      message_count mute_expires_at muted own_capabilities team truncated_at truncated_by type updated_at
    ],
    children: { 'created_by' => :user, 'members' => :member, 'truncated_by' => :user }
  },
  # ChannelMemberResponse
  member: {
    keys: %w[
      archived_at ban_expires ban_from_future_channels banned channel_role created_at deleted_at deleted_messages
      future_channel_ban_expires invite_accepted_at invite_rejected_at invited is_moderator notifications_muted
      pinned_at role shadow_banned status updated_at user user_id
    ],
    children: { 'user' => :user }
  },
  # MessageResponse
  message: { keys: V2_MESSAGE_KEYS, children: V2_MESSAGE_CHILDREN },
  # SearchResult
  search_result: { children: { 'message' => :search_message } },
  # SearchResultMessage
  search_message: {
    keys: V2_MESSAGE_KEYS + %w[channel],
    children: V2_MESSAGE_CHILDREN.merge('channel' => :channel)
  },
  # ReactionResponse
  reaction: { keys: %w[created_at message_id score type updated_at user user_id], children: { 'user' => :user } },
  # Attachment
  attachment: {
    keys: %w[
      actions asset_url author_icon author_link author_name color fallback fields footer footer_icon giphy image_url
      og_scrape_url original_height original_width pretext text thumb_url title title_link type
    ],
    children: {}
  },
  # DraftResponse
  draft: {
    children: {
      'channel' => :channel,
      'message' => :draft_message,
      'parent_message' => :message,
      'quoted_message' => :message
    }
  },
  # DraftPayloadResponse
  draft_message: {
    keys: %w[attachments html id mentioned_users mml parent_id poll_id quoted_message_id show_in_channel silent text type],
    children: { 'attachments' => :attachment, 'mentioned_users' => :user }
  },
  # ThreadStateResponse, a superset of ThreadResponse
  thread: {
    keys: %w[
      active_participant_count channel channel_cid created_at created_by created_by_user_id deleted_at draft
      last_message_at latest_replies parent_message parent_message_id participant_count read reply_count
      thread_participants title updated_at
    ],
    children: {
      'channel' => :channel,
      'created_by' => :user,
      'draft' => :draft,
      'latest_replies' => :message,
      'parent_message' => :message,
      'read' => :wrapper,
      'thread_participants' => :thread_participant
    }
  },
  # ThreadParticipant
  thread_participant: {
    keys: %w[channel_cid created_at last_read_at last_thread_message_at left_thread_at thread_id user user_id],
    children: { 'user' => :user }
  },
  # PollResponseData
  poll: {
    keys: %w[
      allow_answers allow_user_suggested_options answers_count created_at created_by created_by_id description
      description_i18n enforce_unique_vote id is_closed latest_answers latest_votes_by_option max_votes_allowed name
      name_i18n options own_votes updated_at vote_count vote_counts_by_option voting_visibility
    ],
    children: {
      'created_by' => :user,
      'latest_answers' => :wrapper,
      'latest_votes_by_option' => :votes_by_option,
      'options' => :poll_option,
      'own_votes' => :wrapper
    }
  },
  votes_by_option: { map: :wrapper },
  # PollOptionResponseData
  poll_option: { keys: %w[id text text_i18n], children: {} }
}.freeze

def to_v2(value, model = :wrapper)
  case value
  when Array
    value.map { |item| to_v2(item, model) }
  when Hash
    v2_hash(value, V2_MODELS.fetch(model))
  else
    value
  end
end

def v2_hash(hash, model)
  return hash.transform_values { |value| to_v2(value, model[:map]) } if model[:map]

  keys = model[:keys]
  result = {}
  custom = {}
  hash.each do |key, value|
    if keys.nil? || keys.include?(key)
      child = model[:children][key]
      result[key] = child ? to_v2(value, child) : value
    elsif key != 'custom'
      custom[key] = value
    end
  end
  result['custom'] = custom.merge(hash['custom'] || {}) if keys
  result
end

# Rewrites a serialised JSON payload into the v2 shape. Non-JSON payloads pass through.
def to_v2_json(data)
  JSON.pretty_generate(to_v2(JSON.parse(data.to_s)))
rescue JSON::ParserError
  data
end
