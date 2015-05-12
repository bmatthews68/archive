#
# Author:: Brian Matthews (<brian@btmatthews.com>)
# Cookbook Name:: archive
# Library:: archive_helper
#
# Copyright 2015, Brian Matthews
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

$:.unshift *Dir[File.expand_path('../../files/default/vendor/gems/**/lib', __FILE__)]

module Archive
	module Helper
	  	require 'zip'
		require 'zlib'
		require 'rubygems/package'

		TAR_LONGLINK = '././@LongLink'

		class AbstractArchiveSource
			attr_accessor :location

			def initialize(location)
				@location = location
			end
		end

		class NetArchiveSource < AbstractArchiveSource
			def initialize(location)
				super
			end

			def get_stream
				path = File.join(::Chef::Config[:file_cache_path], ::File.basename(@location))
				open(@location) do |fin|
    				File.open(path, "wb") do |fout|
         				while (buf = fin.read(8192))
            				fout.write buf
            			end
        			end
    			end
    			File.open(path, 'rb')
			end
		end

		class LocalArchiveSource < AbstractArchiveSource
			def initialize(location)
				super
			end
			
			def get_stream
				File.open(@location[7..-1], 'rb')
			end
		end

		class CookbookArchiveSource < AbstractArchiveSource
			def initialize(location, run_context, cookbook)
        		root_dir = run_context.cookbook_collection[cookbook].root_dir
       			super(File.join(root_dir, 'files','default', location))
			end
			
			def get_stream
				File.open(@location, 'rb')
			end
		end

		class AbstractUncompressor
			attr_accessor :inclusions
			attr_accessor :exclusions
			attr_accessor :mode
			attr_accessor :dir_mode
			attr_accessor :owner
			attr_accessor :group
			attr_accessor :strip

			def initialize(src_stream, target)
				@src_stream = src_stream
				@target = target
			end

			def match?(patterns, name)
				[*patterns].each do |pattern|
					if File.fnmatch(pattern, name, File::FNM_PATHNAME | File::FNM_DOTMATCH)
						return true
					end
				end
				false
			end

			def include?(name)
				(!match?(exclusions, name)) || match?(inclusions, name)
			end

			def included(name)
			    parts = name.split('/')
            	parts.shift if parts.empty?
            	if parts.length > @strip.to_i
                    parts.shift(@strip.to_i)
                    path = parts.join('/')
                    if include?(path)
                        return File.join(@target, path)
                    end
                end
                nil
            end

			def create_dir(path, owner, group, mode)
				FileUtils.rm_rf(path) unless File.directory?(path)
				FileUtils.mkdir_p(path, { mode: mode}) unless File.exist?(path)
				FileUtils.chmod(@dir_mode, path) unless @dir_mode.nil?
    			FileUtils.chown(@owner || owner, @group || group, path)
			end

			def set_file(path, owmer, group, mode)
				FileUtils.chmod(mode, path) unless mode.nil?
				FileUtils.chmod(@mode, path) unless @mode.nil?
				FileUtils.chown(@owner || owner, @group || group, path)
			end
		end

		class ZipUncompressor < AbstractUncompressor
			def uncompress
				Zip::File.open(@src_stream) do |zip_file|
   					zip_file.each do |entry|
                        path = included(entry.name)
                        unless path.nil?
   						    if entry.ftype == :directory
								create_dir(path, entry.unix_uid, entry.unix_gid, entry.unix_perms)
							end
   						    if entry.ftype == :file
     							FileUtils.rm_rf(path) unless File.file? path
     		    				create_dir(File.dirname(path), entry.unix_uid, entry.unix_gid, 0777)
	        					zip_file.extract(entry, path) { true }
	        					set_file(path, entry.unix_uid, entry.unix_gid, entry.unix_perms)
         					end
						end
   					end
  				end
  			end
		end

		class TarUncompressor < AbstractUncompressor
			def uncompress
				extractor = Gem::Package::TarReader.new(@src_stream)
				extractor.rewind
				filename = nil
				extractor.each do |entry|
				 	if entry.full_name === TAR_LONGLINK
                    	filename = entry.read.strip
                     	next
                    end
                    path = included(filename || entry.full_name)
                    unless path.nil?
                        if entry.directory?
					        create_dir(path, entry.header.uname, entry.header.gname, entry.header.mode)
						end
					    if entry.file?
						    FileUtils.rm_rf(path) unless File.file? path
						    create_dir(File.dirname(path), entry.header.uname, entry.header.gname, 0777)
						    File.open(path, 'wb') do |f|
                        	    f.print(entry.read)
						    end
						    set_file(path, entry.header.uname, entry.header.gname, entry.header.mode)
					    end
					end
					filename = nil
				end
				extractor.close
			end
		end

		class TarGZipUncompressor < TarUncompressor
			def initialize(src_stream, target)
				super(Zlib::GzipReader.open(src_stream), target)
			end
		end

		def create_archive_source(source, run_context, cookbook)
			case
			when source.start_with?('http://', 'https://', 'ftp://')
        		::Chef::Log.info("Source is remote file")
				NetArchiveSource.new(source)
			when source.start_with?('file://')
        		::Chef::Log.info("Source is local file")
				LocalArchiveSource.new(source)
			else
        		::Chef::Log.info("Source is cookbook file")
				CookbookArchiveSource.new(source, run_context, cookbook)
			end
		end

		def create_archive_uncompressor(source, target)
			case
        	when source.location.end_with?('.tar.gz', '.tgz')
        		::Chef::Log.info("Creating uncompressor for GZipped TAR file: #{source.location}")
        		TarGZipUncompressor.new(source.get_stream(), target)
        	when source.location.end_with?('.tar')
        		::Chef::Log.info("Creating uncompressor for TAR file: #{source.location}")
        		TarUncompressor.new(source.get_stream(), target)
        	when source.location.end_with?('.zip', '.jar', '.war')
        		::Chef::Log.info("Creating uncompressor for ZIP file: #{source.location}")
         		ZipUncompressor.new(source.get_stream(), target)
         	else
        		::Chef::Log.info("Cannot create uncompressor for file: #{source.location}")
         		nil
       		end
		end

	end
end