module ActionLinksHelper
  # Destructive Turbo link, with an optional confirmation message.
  def delete_link_to(label, path, confirm: nil, class:)
    link_to label, path, class: binding.local_variable_get(:class), data: { turbo_method: :delete, turbo_confirm: confirm }.compact
  end

  # Button form displayed inline with its surrounding actions.
  def inline_button_to(label, path, **options)
    button_to label, path, **options.deep_merge(form: { style: "display:inline" })
  end
end
