#!/bin/env ruby 


require 'digest/md5'
require 'rubygems'
require 'right_aws'


## don't fail if chef is not installed
if Object.const_defined?("Chef")
  require File.join(File.dirname(__FILE__),'bincache/provider/bincache') 
  require File.join(File.dirname(__FILE__),'bincache/resource/bincache') 
end

class BinCache

  def initialize()
    ## set cache_dir to'/var/tmp/bincache' or ENV['BINCACHE_DIR'] if it is set 
    @cache_dir = (ENV['BINCACHE_DIR']  && ENV['BINCACHE_DIR']) || '/var/tmp/bincache'

    print_and_exit "S3 bucket and path not set. Please set BINCACHE_S3_BUCKET and BINCACHE_S3_PREFIX" unless ENV['BINCACHE_S3_BUCKET'] && ENV['BINCACHE_S3_PREFIX']
    @bucket = ENV['BINCACHE_S3_BUCKET']
    @prefix = ENV['BINCACHE_S3_PREFIX']


    print_and_exit "S3 keys not set. Please set BINCACHE_S3_ACCESS_KEY and BINCACHE_S3_SECRET_KEY" unless ENV['BINCACHE_S3_ACCESS_KEY'] && ENV['BINCACHE_S3_SECRET_KEY']
    @right_s3 = RightAws::S3.new(ENV['BINCACHE_S3_ACCESS_KEY'],ENV['BINCACHE_S3_SECRET_KEY'])
    @right_s3_bucket = @right_s3.bucket(@bucket)
    @right_s3_interface = RightAws::S3Interface.new(ENV['BINCACHE_S3_ACCESS_KEY'],ENV['BINCACHE_S3_SECRET_KEY'])
  end

  def run_series_once(directory=nil, scripts=nil, cwd=nil, hash=nil)
    hash ||= Digest::MD5.hexdigest("#{directory.inspect}#{scripts.inspect}")
    run_series(directory,scripts,cwd) unless File.exist?(File.join(directory,".#{hash}"))
  end

  def run_series(directory, scripts, cwd=nil, hash=nil)
    ## exit if given bogus input
    print_and_exit "bogus input in run_series" if directory.nil? || scripts.nil? 

    ## clear out directory if we are starting a new sequence
    `rm -rf #{directory} && mkdir -p #{directory}` && return if scripts.empty?

    hash ||= Digest::MD5.hexdigest("#{directory.inspect}#{scripts.inspect}")
       
    ## pop the last script   
    pop = scripts.pop

    ## recurse if we have not ran this script yet
    eval("#{__method__}(directory,scripts)")  unless check_for_hash?(hash)

    ## step this script
    step(pop,directory,hash,cwd)
  end

  def check_for_hash?(hash)
    ## return true if the hash is already on our local fs
    return true if File.exists?(File.join(@cache_dir,hash))

    key = RightAws::S3::Key.create( @right_s3_bucket, "#{@prefix}#{hash}" )
    key.exists?
  end

  def step(script,directory,hash,cwd=nil)
    if download_hash? hash
      `rm -rf #{directory}`
      `cd #{File.dirname directory} && tar -xzf #{File.join(@cache_dir,hash)} `
    else
      run_or_exit "mkdir -p #{directory} #{@cache_dir}"
      Dir.chdir cwd unless cwd == nil
      puts "pwd = #{`pwd`}"
      run_or_exit(script, cwd)
      run_or_exit "touch #{File.join directory, '.' + hash }"
      run_or_exit "cd #{File.dirname directory} && tar -czf #{@cache_dir}/#{hash} #{File.basename directory} "
      upload_file("#{@cache_dir}/#{hash}")
    end
  end

  private 

  ## IO.popen 'tar cfz -', 'w+' do |pipe| 

  def upload_file(file)
    key_name = @prefix.dup
    key_name << File.basename(file)
    @right_s3_interface.put(@bucket, key_name , File.read(file) ) 
  end

  def download_hash?(hash)
    ## return true if the hash is already on our local fs
    return true if File.exists?(File.join(@cache_dir,hash))

    ## attempt to download the hash from s3
    begin
      File.open(File.join(@cache_dir,hash) , 'w') {|f| f.write( @right_s3_interface.get_object(@bucket, "#{@prefix}#{hash}") ) }
    rescue 
      return false
    end
    true
  end

  ## This function will compute a recursive md5 hash of a given directory (may be releative)
  ## directory names are taken into consideration
  ## the full path is taken into consideration
  def recurse_and_hash_tree(node)

    ## exit program if given a bunk file/dir
    print_and_exit "given a bunk file/node" unless File.exist? node

    ## if we have a file then return it's hash
    return Digest::MD5.hexdigest( node + File.read(node) ) if File.file? node

    ## we should have a directory now. exit otherwise...
    print_and_exit "is there a strange device in this dir?" unless File.directory? node

    ## recurse through each element in the directory and remember their hashes
    children_hash = ""
    Dir.glob(File.join node, '*' ) { |element| children_hash << recurse_and_hash_tree(element) }
  
    ## return the mashed up hash
    return Digest::MD5.hexdigest( node + children_hash ) 

  end


  def run_or_exit(command,dir=nil)
    Dir.chdir dir unless dir == nil
    script_path = '/tmp/bincache_script'
    File.open(script_path, 'w+') {|f| f.write(command) }
    File.chmod(0544,script_path)
    STDERR.puts "about to execute "
    STDERR.puts "#{command}"
    output = `bash #{script_path}`
    STDERR.puts "output is '#{output}'"
    unless $?.success?
      STDERR.puts "command did not return success '#{command}'"
      STDERR.puts "exiting..."
      Kernel.exit 1
    end
  end


  def print_and_exit(message)
    STDERR.puts "caught an error in bincache" 
    STDERR.puts message
    Kernel.exit 1
  end

end

