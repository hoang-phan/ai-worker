module BadgesHelper
  TONES = %i[success info warning danger neutral].freeze

  def badge(text, tone = :neutral, **options)
    tone = tone.to_sym
    raise ArgumentError, "Unknown badge tone: #{tone}" unless TONES.include?(tone)

    content_tag(:span, text, class: "badge badge-#{tone}", **options)
  end
end
