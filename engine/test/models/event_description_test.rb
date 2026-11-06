# frozen_string_literal: true

require "test_helper"

class EventDescriptionTest < Minitest::Test
  def test_nil_and_plain_descriptions
    description = EventDescription.new(nil)
    assert_nil description.title_override
    assert_nil description.icon
    assert_nil description.countdown_days
    assert_empty description.only_tokens
    refute description.omit?
    refute description.banner?
    refute description.html?
    assert_nil description.without_tokens
    assert_nil description.append([])

    plain = "Meet at 5 < 6 and 8 > 7\nNotes"
    assert_equal plain, EventDescription.new(plain).without_tokens
    refute EventDescription.new("Use <placeholder> here").html?
    assert_nil EventDescription.new("timeframe-title:  ").title_override
  end

  def test_plain_readers_and_first_match_precedence
    description = EventDescription.new("timeframe-title:Local\r\ntimeframe-title:Provider\r\n" \
      "TIMEFRAME-ICON:mdi-star\rtimeframe-only:Kitchen, 12\nTIMEFRAME-COUNTDOWN:007\n" \
      "timeframe-omit\n#banner")
    assert_equal "Local", description.title_override
    assert_equal "star", description.icon
    assert_equal ["Kitchen", "12"], description.only_tokens
    assert_equal 7, description.countdown_days
    assert description.omit?
    assert description.banner?
    assert_nil EventDescription.new("timeframe-countdown:0").countdown_days
    assert_equal 123, EventDescription.new("timeframe-countdown:1234").countdown_days
    assert_nil EventDescription.new("TIMEFRAME-TITLE:Not an override").title_override
    assert_empty EventDescription.new("TIMEFRAME-ONLY:12").only_tokens
    refute EventDescription.new("TIMEFRAME-OMIT TIMEFRAME-BANNER").omit?
    refute EventDescription.new("TIMEFRAME-BANNER").banner?
  end

  def test_html_lines_inline_formatting_and_entities
    description = EventDescription.new("<div>timeframe-title:Run <b>w/ Kevin</b> &amp; Jo&nbsp;</div>" \
      "<p>timeframe-only:Kitchen, 12<br>timeframe-icon:mdi-run</p>" \
      "<div>timeframe-countdown:7</div><div>timeframe-banner</div><p>timeframe-omit</p>")
    assert_equal "Run w/ Kevin & Jo\u00a0", description.title_override
    assert_equal ["Kitchen", "12"], description.only_tokens
    assert_equal "run", description.icon
    assert_equal 7, description.countdown_days
    assert description.banner?
    assert description.omit?

    assert_equal "Run", EventDescription.new("<div>timeframe-title:Run</div><p>Notes</p>").title_override
    assert_equal "Run", EventDescription.new("timeframe-title:Run<br>Notes").title_override
    assert_equal "Run", EventDescription.new("timeframe-title:Run<hr>Notes").title_override
    assert_equal "Run &amp; Jo", EventDescription.new("<p>timeframe-title:Run &amp;amp; Jo</p>").title_override
  end

  def test_case_insensitive_option_for_cloud_compatibility
    source = "<div>TIMEFRAME-TITLE:Run</div><p>TIMEFRAME-ONLY:12</p>" \
      "<p>TIMEFRAME-OMIT</p><p>TIMEFRAME-BANNER</p><p>Notes</p>"
    description = EventDescription.new(source, case_insensitive: true)
    assert_equal "Run", description.title_override
    assert_equal ["12"], description.only_tokens
    assert description.omit?
    assert description.banner?
    refute_includes description.without_tokens, "TIMEFRAME-"
    assert_includes description.without_tokens, "<p>Notes</p>"
  end

  def test_html_nonvisible_content_is_not_metadata
    description = EventDescription.new('<div title="timeframe-omit timeframe-title:Wrong">' \
      "<!-- timeframe-only:12 --><script>timeframe-title:Wrong\ntimeframe-banner</script>" \
      "<style>timeframe-icon:star</style><template>timeframe-countdown:7</template>Notes</div>")
    assert_nil description.title_override
    assert_nil description.icon
    assert_nil description.countdown_days
    assert_empty description.only_tokens
    refute description.omit?
    refute description.banner?
    assert_equal description.without_tokens, description.append([])
  end

  def test_without_tokens_preserves_plain_text_outside_token_spans
    source = "Notes\r\n  timeframe-title:Run\r\n\r\nKeep this\n timeFRAME-icon:mdi-run\n"
    description = EventDescription.new(source)
    assert_equal "Notes\r\n  \r\n\r\nKeep this\n timeFRAME-icon:mdi-run\n", description.without_tokens(:title)
    assert_equal "Notes\r\n  \r\n\r\nKeep this\n \n", description.without_tokens
    assert_equal "Run", description.title_override
    assert_equal source, description.append([])
    assert_raises(KeyError) { description.without_tokens(:unknown) }
  end

  def test_without_tokens_preserves_html_notes_and_inline_markup
    source = "<div>timeframe-title:Run <b>w/ Kevin</b></div><p>Keep <em>these notes</em> " \
      '<a href="https://example.com/?a=1&amp;b=2">link</a></p>' \
      "<div>timeframe-only:12, 15<br>timeframe-countdown:7</div>"
    description = EventDescription.new(source)
    stripped = description.without_tokens(:title, :only)
    assert_includes stripped, "<p>Keep <em>these notes</em>"
    assert_includes stripped, 'href="https://example.com/?a=1&amp;b=2"'
    assert_includes stripped, "timeframe-countdown:7"
    refute_includes stripped, "Run"
    refute_includes stripped, "12, 15"
    assert_equal "Run w/ Kevin", description.title_override
    assert_equal source, description.append([])
    assert_nil EventDescription.new(description.without_tokens).countdown_days
  end

  def test_removal_of_overlapping_tokens
    source = "timeframe-title:Run timeframe-omit\nKeep notes"
    assert_equal "\nKeep notes", EventDescription.new(source).without_tokens
    html = "<p>timeframe-title:Run timeframe-omit</p><p>Keep notes</p>"
    assert_includes EventDescription.new(html).without_tokens, "<p>Keep notes</p>"
  end

  def test_append_plain_and_html_tokens
    assert_equal "timeframe-title:Run", EventDescription.new(nil).append(["timeframe-title:Run"])
    assert_equal "timeframe-title:Run", EventDescription.new("").append(["timeframe-title:Run"])
    assert_equal "Notes\n\n\ntimeframe-title:Run\ntimeframe-icon:run",
      EventDescription.new("Notes\n\n").append(["timeframe-title:Run", "timeframe-icon:run"])
    assert_equal "Notes\n\ntimeframe-title:Run",
      EventDescription.new("Notes").append(["timeframe-title:Run"], separator: "\n\n")
    source = "<p>Keep <em>notes</em></p>"
    appended = EventDescription.new(source).append(["timeframe-title:<Run> & Jo", "timeframe-icon:run"])
    assert_equal source + "<div>timeframe-title:&lt;Run&gt; &amp; Jo</div><div>timeframe-icon:run</div>", appended
    assert_equal "<Run> & Jo", EventDescription.new(appended).title_override
    assert_equal "run", EventDescription.new(appended).icon
  end
end
