module Opscode
  module Application
    module Callbacks
      def self.application_callback(app_id, type = :deploy, &block)
        @application_callbacks ||= {}
        @application_callbacks[app_id] ||= {}
        @application_callbacks[app_id][type] = block
      end

      def self.callback(resource, app_id, type = :deploy)
        return if @application_callbacks.nil?
        app = @application_callbacks[app_id] || return
        return if app.nil?
        cb = app[type]
        return if cb.nil?

        cb.call(resource)
      end
    end
  end
end