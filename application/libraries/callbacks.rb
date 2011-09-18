module Opscode
  module Application
    module Callbacks
      def self.register(recipe, type, app_id = :__default__, &block)
        @callbacks ||= Mash.new
        @callbacks[recipe] ||= Mash.new
        @callbacks[recipe][type] ||= Mash.new
        @callbacks[recipe][type][app_id] ||= []
        @callbacks[recipe][type][app_id] << block
      end

      def self.callback(recipe, type, app_id, args)
        callbacks = @callbacks[recipe][type][app_id] || @callbacks[recipe][type][:__default__] rescue nil
        return if callbacks.nil? || callbacks.empty?

        Chef::Log.info "Running #{type} callbacks in application::#{recipe} for #{app_id}"
        callbacks.each{ |cb| cb.call(args) }
        nil
      end

      def self.callbacks(recipe, type, app_id = :__default__)
        @callbacks[recipe][type][app_id] rescue []
      end
    end
  end
end