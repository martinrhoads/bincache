#!/bin/env ruby 

require 'digest/md5'
require 'rubygems'
require 'right_aws'

class BinCache

  def initialize()
    @bucket = 'devs-us-west'
    @prefix = 'martin/bincache/'
    @download_dir = '/tmp'

    print_and_exit "s3 keys not set. Please set S3_ACCESS_KEY and S3_SECRET_KEY" unless ENV['S3_ACCESS_KEY'] && ENV['S3_SECRET_KEY']

    @right_s3 = RightAws::S3.new(ENV['S3_ACCESS_KEY'],ENV['S3_SECRET_KEY'])
    @right_s3_bucket = @right_s3.bucket(@bucket)
    @right_s3_interface = RightAws::S3Interface.new(ENV['S3_ACCESS_KEY'],ENV['S3_SECRET_KEY'])
  end


  def bincache(script,dir)
    script_hash = Digest::MD5.hexdigest(script)
  end

  def run_series(directory, scripts)
    ## exit if given bogus input
    print_and_exit "bogus input in run_series" if directory.nil? || scripts.nil? 

    ## clear out directory if we are starting a new sequence
    `rm -rf #{directory} && mkdir -p #{directory}` && return if scripts.empty?

    ## hash the scripts
    hash = Digest::MD5.hexdigest(scripts.inspect)
       
    ## pop the last script   
    pop = scripts.pop

    ## recurse if we have not ran this script yet
    eval("#{__method__}(directory,scripts)")  unless check_for_hash?(hash)

    ## step this script
    step(pop,directory,hash)

  end

  def check_for_hash?(hash)
    key = RightAws::S3::Key.create( @right_s3_bucket, "#{@prefix}#{hash}" )
    key.exists?
  end

  def step(script,directory,hash)
    if download_hash? hash
      `rm -rf #{directory}`
      `cd #{File.dirname directory} && tar -xzvf #{File.join(@download_dir,hash)} `
    else
      `mkdir -p #{directory}`
      Dir.chdir directory
      res = `#{script}`
      `cd #{File.dirname directory} && tar -czvf #{@download_dir}/#{hash} #{File.basename directory} `
      upload_file("#{@download_dir}/#{hash}")
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
    begin
      File.open(File.join(@download_dir,hash) , 'w') {|f| f.write( @right_s3_interface.get_object(@bucket, "#{@prefix}#{hash}") ) }
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

  def print_and_exit(message)
    STDERR.puts "caught an error in bincache" 
    STDERR.puts message
    Kernel.exit 1
  end

end

