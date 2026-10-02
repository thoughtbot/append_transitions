# frozen_string_literal: true

require "test_helper"

class TransitionMapTest < Minitest::Test
  def test_allows_initial_state_from_nil
    map = build_map(initial_state: :pending, transitions: {})

    assert map.valid?(from: nil, to: :pending)
  end

  def test_allows_only_initial_state_from_nil
    map = build_map(initial_state: :pending, transitions: {pending: :approved})

    refute map.valid?(from: nil, to: :approved)
  end

  def test_uses_configured_initial_state
    map = build_map(initial_state: :draft, transitions: {})

    assert map.valid?(from: nil, to: :draft)
    refute map.valid?(from: nil, to: :pending)
  end

  def test_allows_only_initial_state_when_transitions_are_empty
    map = build_map(initial_state: :pending, transitions: {})

    refute map.valid?(from: :pending, to: :approved)
  end

  def test_allows_any_state_listed_in_an_array
    map = build_map(initial_state: :pending, transitions: {pending: [:approved, :denied]})

    assert map.valid?(from: :pending, to: :approved)
    assert map.valid?(from: :pending, to: :denied)
  end

  def test_allows_a_state_given_as_a_single_value
    map = build_map(initial_state: :pending, transitions: {denied: :pending})

    assert map.valid?(from: :denied, to: :pending)
  end

  def test_disallows_states_not_listed_for_the_source_state
    map = build_map(initial_state: :pending, transitions: {pending: :approved, denied: :pending})

    refute map.valid?(from: :pending, to: :denied)
    refute map.valid?(from: :denied, to: :approved)
  end

  def test_disallows_any_transition_from_an_unlisted_source_state
    map = build_map(initial_state: :pending, transitions: {pending: :approved})

    refute map.valid?(from: :approved, to: :pending)
    refute map.valid?(from: :unknown, to: :pending)
  end

  def test_normalizes_string_states_to_symbols
    map = build_map(initial_state: "pending", transitions: {"pending" => ["approved"]})

    assert map.valid?(from: nil, to: :pending)
    assert map.valid?(from: :pending, to: :approved)
  end

  def test_raises_when_initial_state_is_not_a_single_state
    error = assert_raises(ArgumentError) do
      build_map(initial_state: [:draft, :pending], transitions: {})
    end

    assert_includes error.message, "initial_state must be a single state"

    assert_raises(ArgumentError) do
      build_map(initial_state: nil, transitions: {})
    end
  end

  def test_raises_when_transitions_have_a_nil_key
    error = assert_raises(ArgumentError) do
      build_map(initial_state: :pending, transitions: {nil => :approved})
    end

    assert_includes error.message, "nil key"
  end

  private

  def build_map(initial_state:, transitions:)
    AppendTransitions::TransitionMap.new(initial_state:, transitions:)
  end
end
