module Opscode
  module Application
    module Helpers
      def database_master(app)
        if app["database_master_role"]
          dbm = nil
          # If we are the database master
          if node.run_list.roles.include?(app["database_master_role"][0])
            dbm = node
          else
          # Find the database master
            results = search(:node, "role:#{app["database_master_role"][0]} AND chef_environment:#{node.chef_environment}", nil, 0, 1)
            rows = results[0]
            if rows.length == 1
              dbm = rows[0]
            end
          end

          unless dbm
            Chef::Log.warn("No node with role #{app["database_master_role"][0]}!")
          end
        end

        if !dbm && app["database_master_hosts"]
          dbm = Chef::Node.new
          dbm['ipaddress'] = app["database_master_hosts"][0]
        end
        dbm
      end

      def memcached_nodes
        if app["memcached_role"]
          unless Chef::Config[:solo]
            memcached_nodes = search(:node, "role:#{app["memcached_role"][0]} AND chef_environment:#{node.chef_environment} NOT hostname:#{node[:hostname]}")
          else
            memcached_nodes = []
          end
          if memcached_nodes.length == 0
            if node.run_list.roles.include?(app["memcached_role"][0])
              memcached_nodes << node
            end
          end
        end

        if !memcached_nodes && app["memcached_hosts"]
          memcached_nodes = app["memcached_hosts"].collect do |server, port|
            cache_node = Chef::Node.new
            cache_node['ipaddress'] = server
            cache_node['memcached'] = {'port' => port}
            cache_node
          end
        end
        memcached_nodes
      end

      def handle_deploy_key(app, recipe)
        if app.has_key?("deploy_key")
          recipe.ruby_block "write_key" do
            block do
              f = ::File.open("#{app['deploy_to']}/id_deploy", "w")
              f.print(app["deploy_key"])
              f.close
            end
            not_if do ::File.exists?("#{app['deploy_to']}/id_deploy"); end
          end

          recipe.file "#{app['deploy_to']}/id_deploy" do
            owner app['owner']
            group app['group']
            mode '0600'
          end

          recipe.template "#{app['deploy_to']}/deploy-ssh-wrapper" do
            source "deploy-ssh-wrapper.erb"
            owner app['owner']
            group app['group']
            mode "0755"
            variables app.to_hash
          end
        end
      end
    end
  end
end