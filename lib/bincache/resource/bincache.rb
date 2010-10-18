require 'chef/resource'

class Chef
  class Resource
    class Bincache < Chef::Resource
      
      def initialize(name, run_context=nil)
        super
        @resource_name = :bincache
        @action = "run"
        @allowed_actions.push(:run)
      end


      def script(arg=nil)
        set_or_return(
          :script,
          arg,
          :kind_of => String
        )
      end


      def directory(arg=nil)
        set_or_return(
          :directory,
          arg,
          :kind_of => String
        )
      end
  
  
      def cwd(arg=nil)
        set_or_return(
          :cwd,
          arg,
          :kind_of => String
        )
      end

      def script_hash(arg=nil)
        set_or_return(
          :script_hash,
          arg,
          :kind_of => String
        )
      end

    end
  end
end
