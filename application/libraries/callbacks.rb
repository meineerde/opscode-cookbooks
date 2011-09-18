module Opscode
  module Application
    module Callbacks
      def self.register(recipe, type, app_id = :__default__, &block)
        @callbacks ||= Mash.new
        @callbacks[recipe] ||= Mash.new
        @callbacks[recipe][type] ||= Mash.new
        @callbacks[recipe][type][app_id] = block
      end

      def self.callback(recipe, type, app_id, args)
        cb = @callbacks[recipe][type][app_id] || @callbacks[recipe][type][:__default__] rescue nil
        return if cb.nil?

        Chef::Log.info "Running #{type} callback in application::#{recipe} for #{app_id}"
        cb.call(args)
      end
    end
  end
end