module Projects
  # True when a project's local directory is the checkout this app is running
  # from (compared by real path, so symlinks to it count). A missing directory
  # or a blank one is not the live checkout.
  class LiveCheckout
    def initialize(local_directory, app_root: Rails.root)
      @local_directory = local_directory
      @app_root = app_root
    end

    def live?
      return false if @local_directory.blank?

      File.realpath(File.expand_path(@local_directory)) == File.realpath(@app_root)
    rescue Errno::ENOENT
      false
    end
  end
end
