require 'chef/config'
require 'chef/log'
require 'chef/provider'

class Chef
  class Provider
    class Bincache < Chef::Provider

      def action_run
        scripts = []

        ## find all of the bincache resources that are running and collect the ones that are operating with the same directory
        bincache_resources = self.run_context.resource_collection.all_resources.select { |r|
          r.class.inspect == self.class.to_s.gsub(/Provider/,'Resource') &&
          r.directory == @new_resource.directory }

        ## add the scripts from each resource to our script list. Stop after we add our own script
        bincache_resources.each do |r|
          scripts << r.script
          break if r.name == @new_resource.name
        end

        ## run bincache
        require 'bincache'
        bincache = BinCache.new
        bincache.run_series(@new_resource.directory,scripts,@new_resource.cwd,@new_resource.script_hash)
      end


      def load_current_resource
        Chef::Resource::File.new(@new_resource.name)
      end

    end
  end
end
