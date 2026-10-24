module SkillPathHelper
  def expand_braces(text)
    match = text.match(/\{([^{}]+)\}/)
    return [ text ] unless match

    match[1].split(",").flat_map do |choice|
      expand_braces(text.sub(match[0], choice))
    end
  end
end
